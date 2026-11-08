# 11 — Seguridad

> Migrado y corregido desde `plans/plan-ecosistema-modular-seguridad.md`. Decisiones: [ADR-0016](../adr/0016-credenciales-por-superficie.md), [ADR-0017](../adr/0017-sesiones-en-bd-sin-devise.md), [ADR-0027](../adr/0027-rate-limiting-en-dos-capas.md). Hitos: M0.07, M0.13, M4.02, M4.03.

## Principios

1. **Deny by default.** Toda ruta exige autenticación y autorización salvo una allowlist explícita y comentada.
2. **Autenticación, tenancy y autorización son capas distintas** ([04](04-access-control.md)).
3. **API-first no es JWT-first.** Cada superficie elige su credencial.
4. **Lo que oculta el frontend no es control de acceso.**
5. **Fallar cerrado y claro:** `401`, `403`, `404`, `409`, `422`, `429`; nunca un `500` por una regla de negocio.
6. **Revocabilidad antes que conveniencia:** toda credencial puede invalidarse sin desplegar.

## Credenciales por superficie

| Superficie | Credencial | CSRF | Clave de rate limit |
| --- | --- | --- | --- |
| Panel (SPA, mismo origen) | Cookie de sesión `httpOnly`, respaldada en BD | Token CSRF + `SameSite=Lax` + validación de `Origin` | IP (Rack::Attack); `user_id` (Rails `rate_limit`) |
| Reserva pública | Ninguna | N/A (sin cookie de sesión) | IP + slug |
| Gestionar cita desde un mensaje | Token firmado de un uso | N/A | token / IP |
| Integraciones | API key opaca (`Bearer`) | N/A | `api_key_id` (Rails `rate_limit`) |
| Webhook de WhatsApp | HMAC `X-Hub-Signature-256` | N/A | fuente |
| Back-office | Sesión de `PlatformStaff` + 2FA obligatorio | Igual que el panel | IP + staff |
| Jobs | `Principal::System` | — | — |
| App móvil (futuro) | JWT corto + refresh rotativo | N/A | `user_id` |

**JWT no entra** hasta que exista una app móvil real (receta abajo).

## Sesiones del panel

- Implementación propia en `platform/identity` partiendo del **generador de autenticación de Rails 8** (`has_secure_password` + modelo `Session` en BD), adaptado a packs. **Sin Devise** ([ADR-0017](../adr/0017-sesiones-en-bd-sin-devise.md)).
- `sessions(id, user_id, token_digest, ip, user_agent, created_at, last_seen_at, expires_at, revoked_at)`.
- Vigencia: inactividad 12 h, absoluta 7 días. `last_seen_at` se actualiza con un throttle de 1 min por sesión.
- Cookie: `Secure`, `HttpOnly`, `SameSite=Lax`, prefijo `__Host-` en producción.
- Rotación del token al iniciar sesión y al elevar privilegios (2FA, cambio de contexto a back-office).
- "Cerrar sesión en todos los dispositivos" = `revoked_at` en todas las sesiones del usuario.

## CSRF (panel)

- Rails en modo API no trae protección CSRF por defecto: se activa explícitamente para los controladores que usan cookie de sesión.
- La SPA obtiene el token desde `/api/v1/me` (o una cookie legible no-`httpOnly` específica) y lo envía en `X-CSRF-Token` en toda mutación.
- Además se valida que `Origin` (o `Referer`) coincida con el origen propio.
- Las requests con API key (`Authorization: Bearer`) **no** usan cookie, así que no aplica CSRF.

## Contraseñas y 2FA

- Mínimo 12 caracteres, sin reglas de complejidad ni rotación forzada; rechazo contra HIBP (k-anonymity).
- **2FA TOTP** (`rotp`) obligatorio para `org_owner`, `org_admin` y `PlatformStaff`; opcional para el resto. 8 códigos de respaldo de un uso, guardados como digest.
- Bloqueo progresivo por cuenta (1, 5 y 15 min…), además del límite por IP.
- Respuesta idéntica en login y en reset de contraseña, exista o no la cuenta.
- Todos los eventos de autenticación (login correcto o fallido, bloqueo, 2FA, reset, revocación) van a `audit_events`.

## API keys

```
api_keys
  id, organization_id, name, token_digest (SHA-256), prefix (8 visibles), scopes text[],
  last_used_at, expires_at NULL, revoked_at NULL, created_by_user_id, timestamps
```

- Formato `cb_live_<32 alfanuméricos>` (`cb_test_` en staging); el token en claro se muestra **una sola vez**.
- Búsqueda por digest; comparación en tiempo constante.
- Máximo 2 claves activas por organización (rotación con 7 días de solapamiento).
- Scopes `read:<modulo>` / `write:<modulo>`, traducidos a permisos por el manifiesto del módulo ([05](05-module-system.md)).
- El principal `ApiKey` tiene alcance de **organización**. Las empresas a las que accede se limitan a las que tienen el módulo activo.

## Enlaces firmados (cliente final)

- Token aleatorio de 32 bytes, guardado como digest, con `purpose` (`manage_appointment`), `appointment_id` y `expires_at` (24 h después de la cita, o 7 días máximo).
- Uso efectivo único: se rota al confirmar una acción (cancelar o reprogramar).
- Se revoca si la cita cambia de estado por otro medio.
- Viaja en la URL (trade-off aceptado y documentado): por eso es de alcance mínimo, caduca y no se loguea (`filter_parameters`).

## Rate limiting en dos capas

**Capa 1: Rack::Attack** (middleware, **antes** de autenticar y sin tocar la BD). Store en Redis, namespace `ratelimit:`. Solo usa claves disponibles sin sesión:

| # | Regla | Clave | Límite / ventana |
| --- | --- | --- | --- |
| 1 | Catch-all | IP | 600 / 5 min |
| 2 | `POST /api/v1/auth/login` | IP | 5 / 15 min |
| 3 | `POST /api/v1/auth/login` | email normalizado (del body) | 10 / 15 min |
| 4 | Reset de contraseña | IP y email | 3 / 1 h |
| 5 | Disponibilidad pública | IP + slug | 60 / 1 min |
| 6 | Crear reserva pública | IP + slug | 5 / 10 min |
| 7 | Webhook de WhatsApp | IP de origen | 600 / 1 min (HMAC verificado en el controlador) |
| 8 | 404/405 repetidos | IP | 10 / 5 min → bloqueo de 1 h |
| 9 | User agent vacío o en la lista de bloqueo | — | bloquear |

**Capa 2: `rate_limit` de Rails 8** (en controladores, **después** de autenticar), con el principal ya resuelto:

| Familia | Clave | Límite / ventana |
| --- | --- | --- |
| API del panel | `user_id` | 2000 / 5 min |
| Reportes | `user_id` | 30 / 1 min |
| API de integradores | `api_key_id` | 120 / 1 min |
| Reportes vía API | `api_key_id` | 10 / 1 min |

> **Corrección respecto a `plans/`:** la tabla original ponía límites por `user_id` en Rack::Attack, "primero en la cadena". En ese punto no hay sesión resuelta y resolverla obligaría a consultar la BD en el middleware. Por eso se divide en dos capas.

- Todos los `429` llevan `Retry-After`, `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset` y un cuerpo problem+json.
- Los límites se configuran por ENV (sin redeploy); dev y test holgados.
- **Proxies de confianza:** configurar `trusted_proxies` para que `remote_ip` sea la IP real tras kamal-proxy, y **verificarlo en los logs** (criterio de aceptación de M0.13).
- **Gotcha NAT:** una clínica con 10 recepcionistas comparte una IP. Por eso nada autenticado se limita solo por IP, más allá del catch-all holgado.
- No se resuelve con rate limiting: cuotas de producto (mensajes por plan), dobles reservas (constraint de BD), límites comerciales por organización.

## Transporte y cabeceras

- Solo HTTPS; HSTS con `preload`.
- **Sin CORS**: todo es del mismo origen. Si algún día existen integradores desde navegador, se agrega una lista explícita de orígenes, nunca `*`.
- En todas las respuestas: `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` mínima, `X-Frame-Options: DENY` (o `frame-ancestors 'none'`).
- **CSP:** estricta en booking (`default-src 'self'`, imágenes del bucket propio, sin `unsafe-inline`); en el panel, CSP con nonces o hashes.
- Uploads (branding): PNG, JPG y WebP; **sin SVG** en el MVP; validación del tipo real (magic bytes) y límites de tamaño.

## Webhooks de WhatsApp

- Se verifica `X-Hub-Signature-256` (HMAC-SHA256 con el app secret) sobre el body crudo, antes de parsear.
- Comparación en tiempo constante; un fallo de firma da `401` y queda en el log.
- Procesamiento asíncrono: el controlador solo guarda el evento entrante y responde `200`; un job lo procesa de forma idempotente por `message_id`.

## JWT: receta si llega la app móvil

Access token de 15 min con algoritmo asimétrico (EdDSA o RS256) y `kid` para rotar; claims `iss`, `aud`, `exp`, `nbf`, `jti`, `sub`; sin PII. Refresh rotativo guardado como digest, con **detección de reuso**: si se reusa, se invalida toda la familia. Denylist por `jti` para el logout. Algoritmos fijados explícitamente; se rechazan `alg: none` y cualquier algoritmo desconocido.

## Dependencias y secretos

- `brakeman`, `bundler-audit` y `pnpm audit` en CI; Dependabot mensual.
- Secretos en Rails credentials y Kamal secrets; runbook de rotación ([10](10-infrastructure.md)).

## Checklist bloqueante para el primer piloto

- [ ] Deny by default con allowlist explícita (M0.07/M0.08)
- [ ] Sesiones en BD revocables y cookies con sus flags (M0.07)
- [ ] CSRF funcional en el panel (M0.07)
- [ ] `Idempotency-Key` en la creación de citas y en el envío de recordatorios (M0.11, M1.05, M3.03)
- [ ] Rack::Attack y `rate_limit` con la IP real verificada (M0.13, M4.02)
- [ ] 2FA obligatorio para `org_owner`, `org_admin` y `PlatformStaff` (M4.02)
- [ ] Principal `User` y `ApiKey` pasando por el mismo Pundit (M0.08)
- [ ] Matriz de autorización en specs (M0.08)
- [ ] Suite de aislamiento de tenant (M0.05) y **RLS activo** (M4.03)
- [ ] `brakeman` + `bundler-audit` en CI (M0.02)
- [ ] Aviso de privacidad y consentimientos según la Ley 787 (M3.01, M4.05)
