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
- **Principal mínimo:** `Identity::Principal::User(id, email, full_name)` en `Current.principal`; `Current.session` es la `Identity::CurrentSession`. Los memberships y `can?(permission, scope)` llegan con M0.08 (`Access::Principal`); hasta entonces nada debe inferir autorización de este objeto.

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

- **El endpoint de ejemplo `GET /api/v1/organizations/:id` ya exige sesión** (deja de ser público), pero **mantiene el flag** `open_organization_endpoint` (solo desarrollo y test; 404 en producción): autenticar no es autorizar, y sin memberships (M0.08) cualquier usuario autenticado podría leer cualquier organización. M0.08 lo autoriza por membership y elimina el flag.
- **Active Storage no dibuja sus rutas** (`config.active_storage.draw_routes = false`): sus subidas directas (`POST /rails/active_storage/direct_uploads`) no pasan por `Api::BaseController` y habrían quedado abiertas sin sesión. El spec lo vigila; se reactivan, autenticadas, cuando un hito use archivos (branding).

## CSRF (panel)

> **Implementado en M0.07** (`Api::Authentication`, `Identity::CurrentSession`).

- Rails en modo API no trae protección CSRF: se implementa en `Api::Authentication`, para todo controlador de la API.
- **Token ligado a la sesión:** `HMAC-SHA256(clave derivada de secret_key_base, id de la sesión)` en hex. Sin estado en BD, distinto en cada sesión, rota con el login, no contiene el token de la cookie ni su digest. Se compara en tiempo constante.
- **Cómo lo obtiene la SPA (desvío de lo que decía este documento):** el cuerpo de `POST /auth/login` y de `GET /auth/session` trae `csrf_token`. Se eligió esto y no `/api/v1/me` (todavía no existe: M0.09) ni una cookie legible no-`httpOnly` (una cookie más que gestionar sin ganar nada: con un XSS caen el token y la sesión por igual). La SPA lo guarda **en memoria** (no en `localStorage`), lo recupera con `GET /auth/session` al recargar y lo envía en `X-CSRF-Token` en **toda mutación** (POST, PUT, PATCH, DELETE). Cuando exista `/me` podrá repetirlo, pero la fuente es la sesión.
- **Sin token (o con uno incorrecto) en una mutación con sesión → `403 auth.csrf_invalid`.** Las lecturas (GET/HEAD/OPTIONS) no lo exigen.
- **Origin:** en toda mutación, si llega `Origin` (o, sin él, `Referer`) debe ser **exactamente** el origen propio (`request.base_url`: esquema + host + puerto). `Origin: null`, otro esquema o puerto, un host que solo contiene el propio o un `Referer` ilegible → `403 auth.origin_forbidden`. Sin ninguno de los dos (curl, clientes que no son navegadores) no se rechaza por Origin: una mutación autenticada igual necesita el token. Un navegador **siempre** envía `Origin` en un POST/DELETE.
- **Orden de los filtros:** Origin (403) → autenticación (401) → token CSRF (403). Una mutación sin sesión responde 401, no 403.
- **Login:** no lleva token (todavía no hay sesión) pero sí la validación de Origin, que frena el "login CSRF" (iniciar la sesión de la víctima en la cuenta del atacante); `SameSite=Lax` tampoco envía cookies en POST entre sitios.
- Las requests con API key (`Authorization: Bearer`) **no** usan cookie, así que no aplica CSRF (M4.02).
- **Pendiente (M0.12):** `packages/api-client` aún no envía `X-CSRF-Token`; el envío automático y la recuperación del token al arrancar llegan con el shell del panel.

## Contraseñas y 2FA

- Mínimo 12 caracteres, sin reglas de complejidad ni rotación forzada; rechazo contra HIBP (k-anonymity).
- **2FA TOTP** (`rotp`) obligatorio para `org_owner`, `org_admin` y `PlatformStaff`; opcional para el resto. 8 códigos de respaldo de un uso, guardados como digest.
- Bloqueo progresivo por cuenta (1, 5 y 15 min…), además del límite por IP.
- Respuesta idéntica en login y en reset de contraseña, exista o no la cuenta. **Login (M0.07):** correo inexistente y contraseña errónea dan el mismo `401 auth.invalid_credentials`, mismo cuerpo (solo cambia `request_id`, que es por petición), sin cookie. `User.authenticate_by` calcula bcrypt también cuando la cuenta no existe, así el tiempo no delata las cuentas (`Identity::Authenticate`; un spec exige que `BCrypt::Engine.hash_secret` se ejecute en ambos caminos). Un valor que no es texto (hash en el JSON) → `400`.
- **Contraseña (M0.07):** `has_secure_password` (bcrypt 3.1.22 fijado), mínimo 12 y máximo 72 bytes (límite de bcrypt, validado por Rails); sin reglas de complejidad. Correo normalizado (`strip` + minúsculas) y `citext` único. HIBP en M4.02.
- **Contraseñas de demo (seeds):** `ceiba-demo-2026` en desarrollo y test (pública y documentada aquí; nunca real). En `RAILS_ENV=production` (producción y staging) los seeds **no crean usuarios** salvo que se defina `SEED_DEMO_PASSWORD`. Los correos usan el dominio reservado `.test`.
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

- [x] Deny by default con allowlist explícita: autenticación (M0.07, spec que recorre todas las rutas); falta la autorización (M0.08)
- [x] Sesiones en BD revocables y cookies con sus flags (M0.07)
- [x] CSRF funcional en el panel: token + Origin en el backend (M0.07); el envío desde el cliente llega en M0.12
- [ ] `Idempotency-Key` en la creación de citas y en el envío de recordatorios (M0.11, M1.05, M3.03)
- [ ] Rack::Attack y `rate_limit` con la IP real verificada (M0.13, M4.02)
- [ ] 2FA obligatorio para `org_owner`, `org_admin` y `PlatformStaff` (M4.02)
- [ ] Principal `User` y `ApiKey` pasando por el mismo Pundit (M0.08)
- [ ] Matriz de autorización en specs (M0.08)
- [ ] Suite de aislamiento de tenant (M0.05) y **RLS activo** (M4.03)
- [ ] `brakeman` + `bundler-audit` en CI (M0.02)
- [ ] Aviso de privacidad y consentimientos según la Ley 787 (M3.01, M4.05)
