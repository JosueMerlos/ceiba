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

> **Implementado en M0.07** (`packs/platform/identity`, `Api::Authentication`, `Api::SessionCookie`). Sin Devise ([ADR-0017](../adr/0017-sesiones-en-bd-sin-devise.md)).

- Partimos del **generador de autenticación de Rails 8** (`has_secure_password` + modelo `Session` en BD), adaptado a packs: `Identity::User` (global, ADR-0028) e `Identity::Session`. Lo que cambió respecto del generador: namespace del pack, API JSON en lugar de vistas, token **guardado como digest**, expiraciones, rotación, CSRF y `Current` con el principal.
- `sessions(id, user_id, token_digest UNIQUE, ip inet, user_agent, last_seen_at, expires_at, revoked_at, created_at, updated_at)`.
- **Token:** `SecureRandom.urlsafe_base64(32)` (256 bits). Solo existe en claro en la cookie del navegador y en el resultado de `Identity::Authenticate`; la BD guarda `SHA-256(token)` (hex). SHA-256 y no bcrypt porque el token tiene entropía de sobra: no hay nada que adivinar por fuerza bruta, y la búsqueda es por igualdad sobre un índice único.
- Vigencia: **inactividad 12 h** (`last_seen_at`) y **absoluta 7 días** (`expires_at`, no se extiende con la actividad). `last_seen_at` se actualiza con un throttle de 1 min por sesión. Una sesión vale si no está revocada, `expires_at > ahora` y `last_seen_at > ahora - 12 h` (`Identity::Session.active`).
- **Cookie** (`Api::SessionCookie`): `HttpOnly`, `SameSite=Lax`, `Path=/`, sin `Domain`, `expires` = caducidad absoluta. `Secure` y prefijo `__Host-` (`__Host-ceiba_session`) con `config.x.auth.secure_cookies`, que es `true` en `RAILS_ENV=production` (producción **y** staging, ADR-0013); en desarrollo y test es `ceiba_session` sin `Secure` (se sirve por HTTP). Rails no escribe una cookie `Secure` en una request HTTP plana.
- **Rails en modo API no trae el middleware de cookies:** `config/initializers/authentication.rb` añade `ActionDispatch::Cookies` explícitamente (y `Api::Authentication` incluye `ActionController::Cookies`). La sesión y el flash de Rails siguen fuera; `spec/config/authentication_config_spec.rb` lo vigila.
- **Rotación:** `Identity::Authenticate` emite SIEMPRE un token nuevo y revoca la sesión que el navegador traía (aunque fuera de otro usuario): un token fijado antes del login no sirve después (fijación de sesión). Con credenciales erróneas no se revoca nada. La rotación al elevar privilegios (2FA, back-office) llega con M4.02.
- "Cerrar sesión en todos los dispositivos" = `revoked_at` en todas las sesiones del usuario (`DELETE /api/v1/auth/sessions`); `DELETE /api/v1/auth/logout` revoca solo la actual. Ambos borran la cookie.
- **Principal:** la sesión entrega `Identity::Principal::User(id, email, full_name)` (solo identidad); desde M0.08 `Access::Authorization` lo envuelve en `Access::Principal::User` (memberships y `can?(permission, scope)`) y ese es el `Current.principal` que ve el resto de la request. `Current.session` sigue siendo la `Identity::CurrentSession`. Ver [04](04-access-control.md#implementación-m008).

### Endpoints

| Endpoint | Auth | Qué hace |
| --- | --- | --- |
| `POST /api/v1/auth/login` | Pública (Origin validado) | `{ email, password }` → `200 { data: { user, csrf_token, expires_at } }` + cookie. Credenciales inválidas → `401 auth.invalid_credentials` |
| `GET /api/v1/auth/session` | Sesión | Misma representación que el login (la SPA lo llama al arrancar para recuperar el token CSRF). Sin sesión → `401 auth.unauthenticated` |
| `DELETE /api/v1/auth/logout` | Sesión + CSRF | Revoca la sesión actual → `204` |
| `DELETE /api/v1/auth/sessions` | Sesión + CSRF | Revoca todas las sesiones del usuario → `204` |

### Deny by default (M0.07)

`Api::BaseController` incluye `Api::Authentication`: **todo controlador de la API exige sesión** (`before_action :authenticate!`) salvo que declare `skip_authentication!` (con un comentario del porqué). El spec `spec/requests/api/authentication_spec.rb` **recorre todas las rutas del router**, llama sin sesión y exige `401` salvo la allowlist de abajo: una ruta nueva que nadie marcó como pública pasa con `401`, y una que quede abierta por descuido rompe el spec. La allowlist no puede quedar obsoleta (cada entrada debe ser una ruta real).

| Ruta pública | Por qué |
| --- | --- |
| `GET /api/health`, `GET /api/ready` | Sondas de Docker/proxy; no heredan de `Api::BaseController` y no devuelven datos |
| `POST /api/v1/auth/login` | Es la puerta de entrada. Protegida por la validación de Origin; el rate limit llega en M0.13 |
| `/api/docs` | Swagger UI y contrato; solo existen en desarrollo, test y staging (`Api::Docs.enabled?`) |

Decisiones tomadas en M0.07:

- **El endpoint `GET /api/v1/organizations/:id`** exige sesión y, desde M0.08, el permiso `platform.organization.read` en una organización donde el usuario tiene membership; el flag temporal `open_organization_endpoint` se eliminó.
- **Active Storage no dibuja sus rutas** (`config.active_storage.draw_routes = false`): sus subidas directas (`POST /rails/active_storage/direct_uploads`) no pasan por `Api::BaseController` y habrían quedado abiertas sin sesión. El spec lo vigila; se reactivan, autenticadas, cuando un hito use archivos (branding).

## CSRF (panel)

> **Implementado en M0.07** (`Api::Authentication`, `Identity::CurrentSession`).

- Rails en modo API no trae protección CSRF: se implementa en `Api::Authentication`, para todo controlador de la API.
- **Token ligado a la sesión:** `HMAC-SHA256(clave derivada de secret_key_base, id de la sesión)` en hex. Sin estado en BD, distinto en cada sesión, rota con el login, no contiene el token de la cookie ni su digest. Se compara en tiempo constante.
- **Cómo lo obtiene la SPA (desvío de lo que decía este documento):** el cuerpo de `POST /auth/login` y de `GET /auth/session` trae `csrf_token`. Se eligió esto y no `/api/v1/me` (todavía no existe: M0.09) ni una cookie legible no-`httpOnly` (una cookie más que gestionar sin ganar nada: con un XSS caen el token y la sesión por igual). La SPA lo guarda **en memoria** (no en `localStorage`), lo recupera con `GET /auth/session` al recargar y lo envía en `X-CSRF-Token` en **toda mutación** (POST, PUT, PATCH, DELETE). Cuando exista `/me` podrá repetirlo, pero la fuente es la sesión.
- **Sin token (o con uno incorrecto) en una mutación con sesión → `403 auth.csrf_invalid`.** Las lecturas (GET/HEAD/OPTIONS) no lo exigen.
- **Origin:** en toda mutación, si llega `Origin` (o, sin él, `Referer`) debe ser **exactamente** uno de los orígenes de `config.x.auth.allowed_origins` (esquema + host + puerto). **No se compara con `request.base_url`**: este sale de `Host`/`X-Forwarded-Host`, que un cliente que llegue directo al puerto de la app puede falsificar (con `X-Forwarded-Host: evil.test` y `Origin: evil.test` habría pasado). La lista viene de la variable `APP_ORIGINS` (orígenes separados por comas; **obligatoria en producción y staging**); sin ella, en desarrollo es `http://localhost:<PUBLIC_PORT|8080>` (el proxy de compose) y en test `http://www.example.com`. En producción sin `APP_ORIGINS` la lista queda vacía y toda mutación con `Origin` se rechaza (**falla cerrado**). `Origin: null`, otro esquema o puerto, un host que solo contiene el propio o un `Referer` ilegible → `403 auth.origin_forbidden`. Sin ninguno de los dos (curl, clientes que no son navegadores) no se rechaza por Origin: una mutación autenticada igual necesita el token. Un navegador **siempre** envía `Origin` en un POST/DELETE. **Pendiente:** `config.hosts` (rechazar `Host` desconocidos) llega con M0.13/M4.04, cuando exista el dominio de producción.
- **Formato de las mutaciones (`ApiRequestGuard`, middleware en `config/middleware/`):** antes de que Rails parsee, enrute o registre nada, toda mutación (POST/PUT/PATCH/DELETE) bajo `/api` debe (1) traer el cuerpo, si lo hay, como `application/json` (`415 request.unsupported_media_type`) y (2) **no traer parámetros en la query string** (`400 request.query_not_allowed`): los secretos no deben viajar en la URL (proxies, historial) y el login no puede abrirse con `?email=…&password=…`. Un formulario HTML de otro sitio solo puede enviar tipos "simples", así que (1) cierra, junto con SameSite, Origin y el token, la vía del POST cross-site sin preflight. Una mutación sin cuerpo ni query (logout) pasa. Las lecturas no se tocan. No hay allowlist: si un hito necesita query en una mutación, se añade aquí con su justificación.
- **Fuga en logs (cerrada):** un cuerpo JSON SIN `Content-Type` lo parsea Rack como formulario y la línea `Parameters:` de Rails lo registraba como *clave* (el filtro de parámetros solo oculta valores), con la contraseña en claro. Al rechazarse en el middleware, el controlador no se ejecuta y esa línea nunca se escribe; `filtered_path` ya filtra la query de la línea `Started`. Cubierto por specs que capturan el log. Un cuerpo JSON correcto sigue filtrando por `filter_parameters`.
- **Orden de los filtros:** Origin (403) → autenticación (401) → token CSRF (403). Una mutación sin sesión responde 401, no 403.
- **Login:** no lleva token (todavía no hay sesión) pero sí la validación de Origin, que frena el "login CSRF" (iniciar la sesión de la víctima en la cuenta del atacante); `SameSite=Lax` tampoco envía cookies en POST entre sitios.
- Las requests con API key (`Authorization: Bearer`) **no** usan cookie, así que no aplica CSRF (M4.02).
- **Pendiente (M0.12):** `packages/api-client` aún no envía `X-CSRF-Token`; el envío automático y la recuperación del token al arrancar llegan con el shell del panel.

## Contraseñas y 2FA

- Mínimo 12 caracteres, sin reglas de complejidad ni rotación forzada; rechazo contra HIBP (k-anonymity).
- **2FA TOTP** (`rotp`) obligatorio para `org_owner`, `org_admin` y `PlatformStaff`; opcional para el resto. 8 códigos de respaldo de un uso, guardados como digest.
- Bloqueo progresivo por cuenta (1, 5 y 15 min…), además del límite por IP.
- Respuesta idéntica en login y en reset de contraseña, exista o no la cuenta. **Login (M0.07):** correo inexistente y contraseña errónea dan el mismo `401 auth.invalid_credentials`, mismo cuerpo (solo cambia `request_id`, que es por petición), sin cookie. `User.authenticate_by` calcula bcrypt también cuando la cuenta no existe, así el tiempo no delata las cuentas (`Identity::Authenticate`; un spec exige que `BCrypt::Engine.hash_secret` se ejecute en ambos caminos). Un valor que no es texto (hash en el JSON) → `400`.
- **Contraseña (M0.07):** `has_secure_password` (bcrypt 3.1.22 fijado), mínimo 12 y máximo 72 bytes (límite de bcrypt, validado por Rails); sin reglas de complejidad. Correo normalizado (`strip` + minúsculas) y `citext` único. HIBP en M4.02. **Riesgo para M4.01 (invitaciones):** `strip` no quita el NBSP (U+00A0) ni normaliza equivalentes Unicode, y `citext` compara con `lower()` del locale; dos correos visualmente iguales pero con distintos codepoints serían cuentas distintas. Al aceptar correos de terceros, normalizar con `unicode_normalize(:nfkc)` y rechazar espacios/controles Unicode antes de guardar.
- **Contraseñas de demo (seeds):** `ceiba-demo-2026` en desarrollo y test (pública y documentada aquí; nunca real). En `RAILS_ENV=production` (producción y staging) los seeds **no crean usuarios** salvo que se defina `SEED_DEMO_PASSWORD`. Los correos usan el dominio reservado `.test`.
- Todos los eventos de autenticación (login correcto o fallido, bloqueo, 2FA, reset, revocación) quedan en la auditoría. **Desvío (M0.11): van a `auth_audit_events`, una tabla GLOBAL hermana de `audit_events`**, no a `audit_events` ([ver Auditoría](#auditoría-append-only-m011)).

## Auditoría append-only (M0.11)

> Código: pack `platform/audit`. Decisión: [ADR-0022](../adr/0022-auditoria-append-only-e-idempotencia.md) (ampliada).

| Tabla | Alcance | Qué registra |
| --- | --- | --- |
| `audit_events` | **tenant** (`organization_id`, política `tenant_isolation`) | Acciones de negocio de una organización: `Audit.record(action:, subject:, before:, after:, metadata:)` |
| `auth_audit_events` | **global** (sin organización) | Identidad: `auth.login_succeeded`, `auth.login_failed`, `auth.logout`, `auth.sessions_revoked` (`Audit.record_auth`) |

- **Por qué dos tablas (decisión de M0.11):** `users` y `sessions` son globales (ADR-0028), un login fallido con un correo sin cuenta no pertenece a ninguna organización, y todavía no hay memberships que digan a cuál atribuirlo. Las alternativas eran (a) `organization_id` NULL solo para la categoría identity en `audit_events` y (b) la tabla global. (a) rompe el guardián de tablas tenant (`organization_id` ⇔ política `tenant_isolation`, y exigiría una política con `OR organization_id IS NULL` que con RLS en M4.03 dejaría **leer los eventos de identidad a todos los tenants**), la FK a `organizations` y la suite de aislamiento; (b) mantiene `audit_events` estricta (`organization_id NOT NULL`, FK, RLS) y no cuesta nada: ambas comparten el mismo trigger. Cuando existan memberships, un evento de seguridad que sí pertenezca a una organización (cambio de rol, invitación) se audita con `Audit.record`; `auth_audit_events` queda para lo que no tiene organización.
- **Append-only por trigger de PostgreSQL** (`reject_audit_mutation`, a nivel de **sentencia**: rechaza aunque el `UPDATE` no toque ninguna fila): `UPDATE`, `DELETE` y `TRUNCATE` fallan con `PG::RestrictViolation` ("… es append-only"), también por SQL crudo como `app_user` (criterio 1). `app_user` además no tiene `TRUNCATE` (privilegio ausente), y el trigger frena el `TRUNCATE` del propio dueño. Un `REVOKE` no habría bastado: `db/structure.sql` se vuelca sin privilegios, el trigger sí viaja. **Límite aceptado:** el dueño (`app_owner`) puede desactivar el trigger (`ALTER TABLE … DISABLE TRIGGER`): es un control contra la **aplicación**, no contra un DBA con privilegios. El modelo además es de solo lectura una vez guardado (`ActiveRecord::ReadOnlyRecord`).
- **Consecuencias operativas:** (1) el FK a `organizations` es `RESTRICT`: una organización con auditoría no se borra; el offboarding (P3) deberá definir un procedimiento privilegiado explícito. (2) Los specs con COMMIT real que auditan limpian con el dueño (`purge_organizations` desactiva el trigger solo dentro de su transacción); la suite normal usa fixtures transaccionales y no deja filas. (3) `db:truncate_all` y `db:seed:replant` fallan con la auditoría presente, a propósito.
- **Actor:** `Audit.record` lo toma de `actor:`, de `Current.principal` o del principal del contexto; sin ninguno es `system` (jobs, seeds, consola). **Contrato de los principales:** un principal declara su tipo con `actor_type` (`user`, `api_key`, `platform_staff`); sin él se deriva del nombre de su clase (`Identity::Principal::User` → `user`). `Access::Principal` (M0.08) debe exponer `actor_type`.
- **Request:** `request_id`, IP (`request.remote_ip`) y user agent salen de `Current` (los fija `Api::RequestMetadata`, incluido en `Api::BaseController`); los jobs no los tienen (NULL).
- **Privacidad del diff** (`Audit::Diff`): solo se guardan las claves de primer nivel que **cambiaron**; los sensibles se **enmascaran como `[FILTERED]`** (la clave se conserva: que cambió una contraseña es un hecho auditable; cuál era, no) con el MISMO criterio que los logs, `ActiveSupport::ParameterFilter` sobre `config.filter_parameters` (`passw`, `email`, `secret`, `token`, `_key`, `crypt`, `salt`, `certificate`, `otp`, `ssn`, `cvv`, `cvc`) más `digest`, `csrf` y `ciphertext`, y **recursivo**: un jsonb `settings: { whatsapp_token: … }` o un array de hashes también se enmascaran. El criterio es por subcadena del nombre, así que enmascara de más (`footprint` contiene `otp`) y nunca de menos; `email` está en la lista, de modo que un cambio de correo sale `[FILTERED]`. Los atributos que el sujeto declara con `encrypts` también salen `[FILTERED]` (se compara el valor real para saber si cambió, pero nunca se almacena). Probado con un modelo con Active Record Encryption real. Una creación pasa solo `after:`, un borrado solo `before:`.
- **Límite de la privacidad del diff:** el filtro es por NOMBRE; no sabe que un campo libre (`notes`, un jsonb) contiene un dato personal. **Regla:** la PII auditable debe ir **cifrada** (`encrypts`) o **auditarse por id** (el sujeto es el registro y el valor no se copia a `before`/`after`/`metadata`). Ver [13](13-privacy-ley-787.md#auditoría-y-datos-personales).
- **Login fallido (criterio 2):** `auth.login_failed` guarda IP, user agent, `request_id`, el `user_id` si la cuenta existe y un **seudónimo del correo normalizado** (`Audit.pseudonymize`: HMAC-SHA256 con clave derivada de `secret_key_base`, como el token CSRF; un SHA-256 simple permitiría confirmar por fuerza bruta qué correos intentaron entrar); nunca la contraseña ni el correo en claro (podría ser PII o una contraseña escrita en el campo equivocado). **Es un dato personal seudonimizado, no anónimo** (la IP y el user agent también lo son): ver la retención propuesta abajo. El evento se escribe fuera de transacción y sobrevive al `401`. La búsqueda de la cuenta se hace SIEMPRE (exista o no) para que ambos fallos hagan el mismo trabajo. `user_id` no lleva FK: la evidencia no debe depender de la vida de la cuenta (anonimización, Ley 787).
- **Falla cerrado:** la auditoría de identidad es parte del login. Un login **correcto** y su evento son atómicos (misma transacción: si falla el evento, no hay sesión) y un login **fallido** cuyo evento no se puede escribir responde `500`, no `401`: preferimos no autenticar ni rechazar en silencio sin dejar rastro. Costo: una indisponibilidad de la tabla de auditoría detiene el login; es el comportamiento buscado en una plataforma que exige trazabilidad.
- **Retención propuesta de `auth_audit_events` (PENDIENTE, dueño: M4.x con el aviso de privacidad y el rate limiting M0.13/M4.04):** IP y user agent son datos personales. Propuesta: conservar 12 meses (ventana útil de investigación de incidentes) y luego borrar o anonimizar (IP truncada, sin user agent), con un procedimiento privilegiado del dueño de la tabla porque el trigger impide el `DELETE` desde la aplicación; particionar por mes (`created_at`) lo haría un `DROP PARTITION`. Sin decidir hasta tener la política de retención de la Ley 787 ([13](13-privacy-ley-787.md)).
- **Conectado:** login correcto o fallido, logout y revocación de todas las sesiones (identity), y `organization.provisioned` (`Audit::ProvisioningHook`, vía `ProvisionOrganization.after_provision`, clave `:audit_organization_provisioned`, desde `config.to_prepare`).
- **Punto de extensión (pendiente, otros hitos):** los cambios de **memberships** (M0.08: `membership.granted/changed/revoked`) se auditan llamando `Audit.record(action:, subject: membership, before:, after:)` desde el servicio que los cambia, dentro de su transacción; no requiere tocar el pack. `Modules::Enable/Disable` (M0.09) igual (`module.enabled/disabled`).
- **Crecimiento:** una fila por acción y por evento de identidad, sin purga ni retención (no se pide). Índices `(organization_id, auditable_type, auditable_id)` y `(organization_id, created_at)`; `auth_audit_events` por `(user_id, created_at)` y `created_at`. Cuando la tabla afecte al rendimiento: particionar por mes (`created_at`) — el trigger y la FK deberán recrearse por partición (ADR-0022).

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

- [x] Deny by default con allowlist explícita: autenticación (M0.07, spec que recorre todas las rutas) y autorización (M0.08: `verify_authorized`/`verify_policy_scoped` globales; `skip_authorization!` con motivo y allowlist)
- [x] Sesiones en BD revocables y cookies con sus flags (M0.07)
- [x] CSRF funcional en el panel: token + Origin en el backend (M0.07); el envío desde el cliente llega en M0.12
- [ ] `Idempotency-Key` en la creación de citas y en el envío de recordatorios (M0.11, M1.05, M3.03)
- [ ] Rack::Attack y `rate_limit` con la IP real verificada (M0.13, M4.02)
- [ ] 2FA obligatorio para `org_owner`, `org_admin` y `PlatformStaff` (M4.02)
- [x] Principal `User` pasando por Pundit (M0.08); `ApiKey` y `PublicToken` existen como interfaz que niega todo hasta M4.02 / M3.04
- [x] Matriz de autorización en specs (M0.08, `bin/ci backend-test`), con la allowlist de `skip_authorization!` verificada contra las rutas reales y los cops `Ceiba/AccessPolicyRoles` y `Ceiba/AuthorizationSkips`
- [ ] Suite de aislamiento de tenant (M0.05) y **RLS activo** (M4.03)
- [ ] `brakeman` + `bundler-audit` en CI (M0.02)
- [ ] Aviso de privacidad y consentimientos según la Ley 787 (M3.01, M4.05)
