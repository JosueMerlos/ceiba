> **HISTÓRICO, no es fuente de verdad.** Desde el 2026-11-07, la documentación vigente vive en [`../docs/`](../docs/README.md). Este archivo se conserva como registro de cómo se llegó a las decisiones; su contenido válido se migró a `docs/` y sus inconsistencias se corrigieron allí (ver `docs/README.md` § Correcciones).

# Seguridad y API-first: ecosistema modular

> Documento de diseño complementario a `plan-ecosistema-modular-modulo-citas.md`.
> Define credenciales, autorización, reglas de rate limiting (Rack::Attack) y endurecimiento general para una arquitectura **API-first**.
> Estado: **decidido** · implementación pendiente · 7 de noviembre de 2026

---

## 0. Principios (no negociables)

1. **Deny by default.** Toda ruta requiere autenticación salvo las explícitamente permitidas. Un endpoint nuevo sin regla de permisos es un bug, no una feature.
2. **Autenticación, autorización y tenancy son tres capas distintas.** Confirmar quién eres (authn), qué puedes hacer (authz, Pundit) y de qué organización eres (tenant). Ninguna sustituye a la otra.
3. **API-first ≠ JWT-first.** "API" significa superficie HTTP con contrato estable, no un esquema de tokens en particular. Cada superficie elige su credencial (ver §1).
4. **Lo que oculta el frontend no es control de acceso.** El backend valida todo; la UI solo refleja.
5. **Fallar cerrado y claro:** `401` sin sesión, `403` sin permiso, `429` con cuota agotada, `409` conflicto de horario. Nunca un `500` por regla de negocio.
6. **Revocabilidad antes que conveniencia.** Toda credencial debe poder invalidarse sin desplegar código.

---

## 1. Superficies y credenciales (la decisión central)

El error clásico de API-first es elegir un único mecanismo de credenciales para todos los casos. Aquí no: cada superficie tiene un modelo distinto.

| Superficie | Cliente | Credencial | CSRF | Clave de rate limit |
| --- | --- | --- | --- | --- |
| Panel (SPA) | Navegador del staff | **Cookie de sesión httpOnly** | Token/SameSite + `Origin` | `user_id` |
| Reserva pública | Anónimo en móvil (Instagram/WhatsApp) | Ninguna; ficha previa | N/A | IP + slug (con ajuste anti-NAT, ver §4.2) |
| Cancelar/reprogramar desde correo | Cliente con enlace firmado | **Token firmado de un uso** | N/A | token |
| API para integraciones | Servidor de terceros / futura app | **API key opaca** (`Bearer`) | No aplica | `api_key_id` |
| Webhooks entrantes (WhatsApp) | Meta | **Verificación HMAC** (`X-Hub-Signature-256`) | No aplica | fuente |
| Jobs de fondo (Sidekiq) | Sistema | Credenciales del sistema; nunca leer `Current` | No aplica | — |
| App móvil (Fase futura) | App instalada | **JWT de vida corta + refresh rotativo** | No aplica | `user_id` |

**Consecuencias directas:**

- El panel NO usa JWT. Una SPA con sesión por cookie `httpOnly` es más segura que tokens en `localStorage`: el XSS no roba la sesión (JS no puede leer la cookie) y el cierre de sesión es inmediato.
- La API de integraciones NO usa JWT largo. Usa API key opaca revocable. JWT hereda una revocación complicada por diseño (stateless).
- JWT entra **únicamente** cuando exista una app móvil (Fase ~5), con el diseño de §2.4.

### 1.1 Por qué no JWT para todo (y cuando sí)

| | API key opaca | JWT largo | JWT corto + refresh |
| --- | --- | --- | --- |
| Revocación inmediata | ✅ (DELETE en BD) | ❌ sin denylist central | ⚠️ refresh con detección de reuso |
| Costo por request | O(1) con caché | O(0) tras validar firma | Alta rotación |
| Complejidad | Baja | Media | Alta (rotación, denylist, `jti`) |
| Riesgo si se filtra | Bajo (revocas) | Alto (válido hasta expirar) | Medio (ventana corta) |
| Cuándo usarlo | Integraciones y MVP | Nunca como sesión de browser | App móvil o muchos verificadores |

**Recomendación:** empezar sin JWT. Agregarlo cuando una app móvil real lo exija, con la receta de §2.4. Este es el punto donde más código se escribe "por si acaso" y luego es lío de mantenimiento.

---

## 2. Autenticación por superficie

### 2.1 Panel: sesión en BD, no solo cookie firmada

- Implementación mínima en el pack `core` (`has_secure_password`), sin Devise: Devise reparte controladores por toda la aplicación y se pelea con los packs de Packwerk.
- **Sesión persistida en tabla `sessions`** con `user_id, session_token_digest, ip, user_agent, created_at, last_seen_at, revoked_at`.
  - Motivo: una cookie firmada (Rails por defecto) **no se puede revocar del lado del servidor**. "Cerrar sesión en todos los dispositivos" es imposible con un store de solo cookie.
- Vigencia: ociosa 12 h, absoluta 7 días.
- Cookie con banderas: `Secure`, `HttpOnly`, `SameSite: Lax`, `Path: /`; en producción con prefijo `__Host-` si el dominio lo permite.
- Rotación del id de sesión al iniciar sesión (mitiga fijación de sesión).

### 2.2 Contraseñas y 2FA

- Mínimo **12 caracteres**, sin reglas de complejidad absurdas; rechazo contra la base de filtraciones vía HIBP (k-anonymity, sin enviar la contraseña).
- **2FA TOTP obligatorio** para `org_owner` y `org_admin` (QR generado con `rotp`), con 8 códigos de respaldo de un uso.
- Bloqueo progresivo por cuenta tras intentos fallidos (1 min, 5 min, 15 min…) — no solo límite por IP, que se evita cambiando IP.
- Cada evento de autenticación (login ok, login fallido, lockout, 2FA) va a `audit_events` con IP y user agent. Hoy `audit_events` cubre negocio, no auth: se amplía.

### 2.3 API keys para integraciones

```
api_keys
  id
  organization_id      # el tenant de la clave
  name                 # "Club Magno - reporting"
  token_digest         # SHA-256, única búsqueda y comparación en tiempo constante
  prefix               # primeros 8 caracteres visibles (identificación de UI)
  scopes               # ["read:appointments", "write:appointments"]
  last_used_at
  expires_at           # opcional
  revoked_at
  created_by_user_id
```

- El token en claro se muestra **una sola vez** (`ok_live_` + 32 alfanuméricos); la BD guarda solo el digest.
- Rotación: máximo 2 claves activas por organización; nueva válida inmediatamente, la vieja sigue 7 días con la marca «rotación en curso».
- Scopes en el MVP: `read` y `write` con sufijo de módulo. Nada de scopes finos todavía.
- La API key **actúa como principal**: `Current.context` se instancia con `organization:` de la clave y `user: nil`. Las policies de Pundit aceptan ambos principals (ver §3).

### 2.4 JWT — receta si llega la app móvil

- Algoritmo asimétrico con rotación de clave (`kid`): EdDSA (Ed25519) o RS256. **Nunca HS256 con secreto compartido** entre servicios.
- Access token: **15 minutos**, claims `iss, aud, exp, nbf, jti, sub`; sin datos personales en el payload.
- Refresh token: rotativo, guardado por digest en BD, **detección de uso reutilizado** → al detectar reuso se invalida la familia completa (posible robo).
- Denylist por `jti` para logout (con TTL = vida del token).
- Algoritmos fijados explícitamente en la validación; rechazar `alg: none` y `alg` desconocidos.

### 2.5 Enlaces firmados públicos (cancelar/reprogramar)

- Ya está previsto token no adivinable; añadir: un solo uso efectivo (se rota al confirmar), expiración 24 h, y revocación inmediata si el cliente marca la cita como pagada/cancelada por otro medio.

---

## 3. Autorización: Pundit sí, CanCanCan no

El plan ya decidió Pundit. Confirmo la decisión **en contra de CanCanCan** y con razones de arquitectura, no de gusto:

| | Pundit | CanCanCan |
| --- | --- | --- |
| Organización | Una policy por modelo, por pack | **Un Ability gigante** centralizado |
| Encaje con Packwerk | ✅ la policy vive junto a su pack; dependencias explícitas | ❌ el Ability cruza todos los límites de módulo |
| Scopes de consulta (`resolved_scope`) | ✅ nativo | Manual en cada controlador |
| Testing | Specs más simples | Reglas en un hash, más difícil de aislar |

El Ability único de CancanCan se convierte en un **god object** que toca todos los packs: exactamente lo que Packwerk existe para evitar. En un monolito modular, la autorización debe ser tan modular como el código que la usa.

**Única alternativa digna: ActionPolicy** (evilmartians), con scoping, composición y caché superiores. Decisión explícita: **seguimos con Pundit** — ya está escrito en el plan, el equipo lo sabe y cambiar de gema ahora no compra nada.

### 3.1 Principal: usuario o API key

Nueva pieza necesaria para API-first:

```
Current.principal = Principal::User(user, context)      # panel
                  | Principal::ApiKey(api_key, context) # integraciones
                  | Principal::System                   # jobs internos
```

- Las policies preguntan "¿puede **principal** hacer X?", no "¿puede **user** hacerlo?".
- El `org_owner` del panel y la API key de reporting que consultan datos del mismo cliente llegan por el mismo Pundit, con scopes distintos.

### 3.2 Reglas duras de autorización

- `authenticate!` en `ApplicationController`; cada controller público lo desactiva **explícitamente** y con comentario.
- Los `company_id` y `branch_id` **nunca** vienen del cliente: se derivan del contexto de ruta (`/api/v1/organizations/:org/companies/:company`) resolviendo y validando contra el scope del principal.
- Index siempre con `policy_scope`, nunca `Model.all`.
- Escritura con `authorize` en cada mutación; las mutaciones masivas pasan por servicios de dominio, no por `update`.

---

## 4. Rate limiting (Rack::Attack) — reglas concretas

### 4.1 Dónde vive y con qué store

- Gem `rack-attack`, montado como middleware, **primero en la cadena** (antes que authn y tenancy): un atacante sin credenciales debe ser frenado sin tocar la BD.
- **Store: Redis, no el Rails.cache por defecto.** Rails 8 trae Solid Cache (disco): contar peticiones en disco por request es una desventaja de rendimiento y escritura. Reutilizar el Redis de Sidekiq con otro namespace (índice de BD 1 o prefijo `ratelimit:`).
- Configurar proxies de confianza: tras Kamal-proxy/Docker, `request.remote_ip` puede ser la IP interna del contenedor. Añadir las IP del proxy a `config.action_dispatch.trusted_proxies` y **verificar en logs que la IP real llega**. Si esto está mal, un límite por IP agrupa TODAS las peticiones como una sola.
- Excluir de límites: `/health`, `/ready` (ya previstos) y el healthcheck del deploy.
- Todas las respuestas 429: `Retry-After` + cabeceras de límite drafts (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`) + cuerpo problem+json. Registrar evento (log + Sentry en patrones repetidos).

### 4.2 Clave de límite: el gotcha multi-tenant

**Limitar solo por IP rompe oficinas reales.** Una clínica con 10 recepcionistas comparte una IP de salida: 200/5min por IP es un falso positivo un lunes a las 10 a. m., y el staff pierde confianza en el sistema el primer día.

| Contexto | Clave |
| --- | --- |
| Autenticado (panel/API) | `user_id` o `api_key_id` — **nunca solo IP** |
| Anónimo (pública) | IP **+ slug de empresa** (reparte hasta oficinas/proxies compartidos) |
| Login/reset | IP **y** cuenta (e-mail), se aplica el más estricto |

### 4.3 Políticas (números por defecto, ajustables por entorno)

| # | Endpoint / familia | Clave | Límite | Ventana | Extra |
| --- | --- | --- | --- | --- | --- |
| 1 | Global catch-all | IP | 600 | 5 min | Absorbe scrapers y sondeos |
| 2 | `POST /auth/login` | IP | 5 | 15 min | Con lockout por cuenta (§2.2) |
| 3 | `POST /auth/login` | cuenta | 10 | 15 min | |
| 4 | reset de contraseña | IP y cuenta | 3 | 1 h | Respuesta idéntica exista o no la cuenta |
| 5 | Disponibilidad pública | IP+slug | 60 | 1 min | Endpoint barato |
| 6 | Crear reserva pública | IP+slug | 5 | 10 min | `idempotency_key` obligatoria (ya en plan) |
| 7 | API panel autenticada | `user_id` | 2 000 | 5 min | Bulk de calendario está dentro |
| 8 | Reportes (scoped por usuario) | `user_id` | 30 | 1 min | Consultas pesadas |
| 9 | API integradores | `api_key_id` | 120 | 1 min | Más cuota si sondeamos demanda |
| 10 | Reportes vía API | `api_key_id` | 10 | 1 min | |
| 11 | Webhook WhatsApp | fuente | 600 | 1 min | **HMAC verificado antes de contar** |
| 12 | Rutas 404/405 repetidas | IP | 10 | 5 min | `fail2ban`: bloque 1 h (scanning) |
| 13 | UAs vacías / crawlers conocidos maliciosos | cada request | bloquear | — | lista mantenida con criterio |

### 4.4 Qué NO resolver con Rack::Attack

- Cuotas de producto (mensaje de WhatsApp por organización, límite de sucursales del plan) → lógica de dominio, no middleware de abuso.
- Coordinación anti-doble-reserva → la constraint de BD (ya en plan).
- Límites por organización en API pesada → app layer con factura (por si un integrador justifica plan superior).

### 4.5 Pruebas

- Spec de Rack::Attack por política con `freeze_time` y reset del store entre ejemplos.
- Un test end-to-end del falso positivo de NAT: 6 usuarios distintos tras una IP no deben bloquearse (valida §4.2).
- `brakeman` + `bundler-audit` en CI, en la misma suite donde corre Packwerk.

---

## 5. Transporte, cabeceras y CORS

- HTTPS único; `Strict-Transport-Security` con `preload`; rechazar HTTP.
- **CORS explícito**, nunca `*`: lista de orígenes por entorno (`panel.midominio.com`); la reserva pública es server-rendered desde el mismo origen, no una cross-origin API.
- Cabeceras en **todas** las respuestas: `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` mínima.
- CSP estricta para la **página pública** (server-rendered): `default-src 'self'`, sin `unsafe-inline` si se puede; para la SPA se relaja con nonces.
- Sin secretos ni token en URLs (los logs los copian). El token de enlaces públicos viaja en query pero es de un solo uso y expira (trade-off aceptado y documentado).
- Logs: nunca PII de más ni cuerpo de requests con datos de salud; ya hay `request_id, organization_id, company_id, branch_id` (§7 del plan).

---

## 6. Dependencias y operación

- `brakeman` y `bundler-audit` en CI; actualización mensual planificada de Dependabot.
- Secretos en `Rails credentials` / `kamal secrets`; runbook de rotación (DB, Redis, API de Meta, claves de firma JWT).
- Log retention 90 días; retención de `audit_events` indefinida (append-only).
- Respaldo diario **cifrado** + simulacro trimestral de restauración (ya en plan).

---

## 7. Checklist: bloqueos para el primer piloto (Fase 4)

- [ ] `authenticate!` deny-by-default con allowlist explícita.
- [ ] Sesiones en BD revocables + flags de cookie.
- [ ] `idempotency_key` en creación de citas y en envío de recordatorios.
- [ ] Rack::Attack con Redis + proxy de confianza verificado en logs.
- [ ] CSRF funcional en el panel (token o `SameSite` + `Origin`).
- [ ] 2FA obligatorio para `org_owner`/`org_admin` (opcional para el resto).
- [ ] `principal` (user/api_key) pasa por el mismo Pundit.
- [ ] Matriz rol × alcance × recurso en specs (§7 del plan).
- [ ] Spec de fuga de tenant sobre todos los modelos (§7 del plan).
- [ ] `brakeman` + `bundler-audit` en CI.
- [ ] `429` con cabeceras de límite y `Retry-After`.
- [ ] Aviso de privacidad y consentimiento de recordatorios (LFPDPPP, ya en plan).

---

## 8. Decisiones cerradas (7 de noviembre de 2026)

| # | Decisión | Resolución |
| --- | --- | --- |
| 1 | Sesión del panel | **BD revocable** (tabla `sessions`): logout total por usuario; coste de 1 query indexada por request |
| 2 | Contraseñas | **Mínimo 12 caracteres + HIBP** (k-anonymity). Sin reglas de complejidad ni rotación forzada |
| 3 | 2FA TOTP | **Obligatorio** para `org_owner`/`org_admin`; **opcional** para el resto del staff |
| 4 | Scopes de API key | **`read:`/`write:` con sufijo de módulo** (`read:appointments`, `write:appointments`, …) |
| 5 | Números de límites | **Tabla §4.3 como default de producción**; dev/test holgados; valores por ENV sin redeploy. Se calibran con datos de los pilotos |
| 6 | Visibilidad de throttling | **Log estructurado + Sentry**; endpoint/dashboard interno postergado a Fase 5–6 |

No quedan decisiones de diseño abiertas en este documento. Los valores de los límites se recalibrarán con datos reales de la Fase 4 — eso es tarea operativa, no una decisión pendiente.

---

## 9. Referencias

- `plan-ecosistema-modular-modulo-citas.md` — plan cerrado (232 líneas).
- `plan-ecosistema-modular-pendientes.md` — análisis abierto (branding, roles, onboarding, cobro).
- `plan-ecosistema-modular-modulo-citas-bk.md` — original respaldado.
