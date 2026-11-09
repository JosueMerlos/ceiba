# 07 — Contrato API

> Decisiones: [ADR-0012](../adr/0012-contrato-openapi-y-cliente-generado.md), [ADR-0016](../adr/0016-credenciales-por-superficie.md). Hito: M0.06 (y cada hito que agrega endpoints). Estado: **implementado en M0.06; la autenticación, CSRF y los endpoints `auth` en M0.07** (errores, paginación, serializers, contrato, cliente y check de drift); lo que sigue pendiente se marca en cada sección.

## Principios

1. **El contrato es un artefacto versionado**: `backend/openapi/v1.yaml`, generado a partir de los specs de rswag y commiteado.
2. **El frontend nunca escribe tipos a mano** para respuestas de la API: los genera desde el contrato.
3. **CI falla si el contrato y el cliente generado divergen**, o si un endpoint no está documentado.

## Superficies

| Prefijo | Consumidor | Credencial |
| --- | --- | --- |
| `/api/v1/...` | Panel (SPA) e integradores | Cookie de sesión (M0.07) **o** API key (`Authorization: Bearer`, M4.02) |
| `/api/public/v1/c/:slug/...` | `apps/booking` (anónimo) | Ninguna; rate limit por IP + slug |
| `/api/public/v1/manage/:token/...` | Cliente con enlace firmado | Token de un uso |
| `/api/platform/...` | Back-office | Sesión de `PlatformStaff` + 2FA |
| `/api/webhooks/whatsapp` | Meta | HMAC `X-Hub-Signature-256` |

## Recursos y contexto en la ruta

```
/api/v1/me
/api/v1/organizations/:organization_id/companies
/api/v1/organizations/:organization_id/companies/:company_id/branches
/api/v1/organizations/:organization_id/companies/:company_id/appointments?branch_id=…
```

- `organization_id`, `company_id` y `branch_id` **nunca** vienen del body: salen de la ruta (o de un filtro validado) y se cruzan con los memberships del principal.
- Profundidad máxima: organización → empresa → recurso. La sucursal va como filtro o atributo, no como cuarto nivel de anidación.

## Convenciones

| Tema | Convención |
| --- | --- |
| Formato | JSON; claves en `snake_case`; fechas ISO 8601 en **UTC** con `Z`; la zona de la sucursal se entrega aparte (`branch.time_zone`) |
| IDs | UUIDv7 como string |
| Dinero | `{ "amount_minor": 150000, "currency": "NIO" }`; nunca floats |
| Serialización | **Alba** (rápido, explícito); un serializer por representación |
| Paginación | **Por cursor**: `?limit=50&after=<cursor opaco>` → `{ data: [...], page: { next_cursor, has_more } }`. Nada de `OFFSET` |
| Filtros | Parámetros explícitos y documentados (`?status=scheduled&from=…&to=…`); nada de filtros genéricos tipo `q[...]` |
| Escrituras idempotentes | Header `Idempotency-Key` obligatorio en la creación de citas (panel y pública) y recomendado en cualquier `POST` |
| Concurrencia optimista | `lock_version` en los recursos editables; un `PATCH` con versión vieja → `409` |
| Versionado | `/v1` en la ruta. Agregar campos no rompe; quitar o renombrar exige `v2`. Política de deprecación: header `Sunset` + 6 meses |

## Errores: `application/problem+json` (RFC 9457)

```json
{
  "type": "urn:ceiba:error:appointments.slot_unavailable",
  "title": "El horario ya no está disponible",
  "status": 409,
  "code": "appointments.slot_unavailable",
  "detail": "Otro cliente reservó ese horario hace un momento.",
  "instance": "/api/v1/organizations/…/appointments",
  "request_id": "…",
  "errors": [{ "field": "starts_at", "code": "taken", "message": "…" }]
}
```

| Status | Cuándo |
| --- | --- |
| 400 | Request mal formada (JSON inválido, parámetro de tipo incorrecto) |
| 401 | Sin credencial válida |
| 403 | Autenticado pero sin permiso |
| 404 | No existe **o** no es visible para el principal **o** el módulo está inactivo (no se revela la existencia) |
| 409 | Conflicto: horario tomado, transición de estado inválida, `lock_version` vieja, `Idempotency-Key` reutilizada con otro cuerpo |
| 422 | Validación de dominio (con `errors[]` por campo) |
| 429 | Rate limit, con `Retry-After` y cabeceras `RateLimit-*` |
| 500 | Solo bugs. **Nunca** una regla de negocio |

`code` es estable y traducible: el frontend lo mapea a mensajes con i18n.

### Implementación (M0.06)

- **Un solo constructor:** `Api::Problem` arma el cuerpo (`type`, `title`, `status`, `code`, `instance`, `request_id` y, solo si el error los define, `detail` y `errors[]`). `Content-Type: application/problem+json`. `request_id` es el de `X-Request-Id` (se respeta el que manda el cliente y siempre se devuelve la cabecera).
- **Rescates centralizados** en `Api::BaseController` (concern `Api::ErrorHandling`): todo controlador de la API hereda de él (`Api::V1::<Pack>::XController < Api::BaseController`). Los errores que ocurren **antes** de llegar a un controlador (JSON mal formado en el cuerpo, ruta inexistente) los cubren `config.exceptions_app` (`Api::ExceptionsApp`); fuera de `/api` Rails responde como siempre. Las sondas `/api/health` y `/api/ready` **no** heredan de `Api::BaseController`: son infraestructura y siguen devolviendo su JSON simple.
- **Registro de errores de dominio → `code`:** `Api::ErrorRegistry.register(Clase, status:, code:, title:, detail:, errors:)`. Cada pack registra lo suyo en `config/initializers/api_errors.rb` (dentro de `to_prepare`); el registro de plataforma (`backend/config/initializers/api_errors.rb`) cubre Active Record, parámetros y paginación. Se resuelve por la clase más específica de la jerarquía; `code` es **único** (registrar el mismo para dos clases lanza `ArgumentError`). `status`, `code`, `title`, `detail` y `errors` aceptan un valor o un callable que recibe la excepción. **El mensaje de la excepción nunca sale por defecto**: lo que se expone lo decide el registro.
- **`title` por i18n:** clave `api.errors.<code>` en el locale `es-NI` (de la plataforma o del pack); sin traducción, la frase estándar del status.
- **`type` es un URN estable** (`urn:ceiba:error:<code>`), no una URL (**desvío** de lo que decía este documento): todavía no hay dominio de documentación y un URL inexistente sería una referencia colgante. RFC 9457 admite cualquier URI; cuando exista el dominio se cambia en un solo sitio (`Api::Problem#to_h`) sin tocar los `code`.

| `code` | Status | Origen |
| --- | --- | --- |
| `route.not_found` | 404 | Ruta inexistente bajo `/api`; también el endpoint de ejemplo cuando está desactivado |
| `resource.not_found` | 404 | `ActiveRecord::RecordNotFound` (incluye un id que no es UUID) |
| `validation.failed` | 422 | `ActiveRecord::RecordInvalid`; `errors[]` = `{ field, code, message }` por cada error de Active Model |
| `resource.stale` | 409 | `ActiveRecord::StaleObjectError` (`lock_version` vieja) |
| `resource.conflict` | 409 | `ActiveRecord::RecordNotUnique` (sin exponer SQL ni nombre de índice) |
| `request.invalid` | 400 | Parámetro obligatorio ausente (`errors[]` con el campo) |
| `request.malformed` | 400 | JSON mal formado |
| `request.unsupported_media_type` | 415 | Mutación con cuerpo que no es `application/json` (`ApiRequestGuard`) |
| `request.query_not_allowed` | 400 | Mutación con parámetros en la query string |
| `request.bad_request` | 400 | `ActionController::BadRequest` |
| `pagination.invalid_cursor` / `pagination.invalid_limit` | 400 | Cursor manipulado o `limit` fuera de 1–100 |
| `tenancy.slug_taken` | 409 | `Tenancy::ProvisioningFailed(:slug_taken)` |
| `tenancy.slug_reserved` / `tenancy.invalid` | 422 | `Tenancy::ProvisioningFailed`; `errors[]` con `company.slug`, etc. |
| `tenancy.inconsistent_context` | 404 | `Tenancy::InconsistentContext` (no se revela qué entidad existe) |
| `auth.unauthenticated` | 401 | Sin sesión válida (cookie ausente, desconocida, revocada o vencida). **Toda** ruta de la API lo devuelve salvo la allowlist ([11](11-security.md#deny-by-default-m007)) |
| `auth.invalid_credentials` | 401 | Login con correo inexistente **o** contraseña errónea (misma respuesta) |
| `auth.csrf_invalid` | 403 | Mutación con sesión sin `X-CSRF-Token` correcto |
| `auth.origin_forbidden` | 403 | Mutación con `Origin`/`Referer` que no es el origen propio |
| `idempotency.key_reused` | 409 | `Idempotency-Key` ya usada con otro método, ruta o cuerpo (M0.11) |
| `idempotency.key_required` / `idempotency.key_invalid` | 400 | Endpoint con `required: true` sin el header; clave vacía, de más de 255 caracteres o no ASCII imprimible (M0.11) |
| `internal.error` | 500 | Cualquier excepción sin registrar |

- **`Tenancy::TenantMismatch` y `Tenancy::TenantIsImmutable` no se registran a propósito:** solo se lanzan si el servidor intentó escribir en otro tenant, es decir, ante un **bug**. Responden `500 internal.error` genérico y el detalle va al log. Si algún día una regla de negocio los lanzara de forma legítima, se registran con su status.
- **Errores de cliente no registrados:** si Rails ya clasifica la excepción con un status < 500 (método HTTP desconocido, token inválido...), se responde ese status con `code: "http.<status>"` y **no** se reporta como bug; están registrados con code propio `request.method_not_allowed` (405), `request.not_acceptable` (406), `request.unknown_format` (406) y `request.not_implemented` (501). Solo `internal.error` se reporta. Fuera de `/api`, `exceptions_app` delega en Rails con el `env` intacto.
- **Un 500 nunca lleva stacktrace ni detalles internos, tampoco en desarrollo:** el cuerpo es `{ type, title, status, code, instance, request_id }` y nada más. El detalle real (clase, mensaje, backtrace limpio) va a `Rails.logger.error` y a `Rails.error.report` (donde se enganchará el servicio de errores), etiquetado con el `request_id`; quien depura busca ese id en el log. Para que valga también en desarrollo y test, `consider_all_requests_local = false` en esos entornos (sin la página de depuración de Rails, que mostraría el trace como JSON).

## Paginación por cursor (M0.06)

`Api::Pagination::Cursor.paginate(scope, limit:, after:)` → `{ records, next_cursor, has_more }`; en un controlador, `render_page(scope, serializer: XSerializer)` responde `{ "data": [...], "page": { "next_cursor": "…", "has_more": true } }`.

- **Orden = clave primaria ascendente.** El UUIDv7 lleva el instante de creación en sus primeros bits ([09](09-data-conventions.md)), así que ordenar por id es ordenar por creación. Las filas **confirmadas antes de empezar el recorrido** no se duplican ni se omiten aunque se inserten otras entre páginas (con `OFFSET`, una inserción las desplazaría). Criterio 6: 120 registros con `limit=50` → 3 páginas (50, 50, 20), también con inserciones entre páginas.
- **Límite conocido (concurrencia):** el id se genera en el `INSERT`, no en el `COMMIT`, y `uuidv7()` solo es monótono **dentro de una sesión**; además se pueden fijar ids explícitos. Una fila insertada concurrentemente puede quedar con un id menor que el cursor y no aparecer en ese recorrido (sí en el siguiente). Es la garantía de un listado, no la de un log de eventos (para eso está el outbox).
- **Índice:** para listados de tablas tenant, `(organization_id, id)` (la paginación filtra por tenant y ordena por `id`); la PK sola obligaría a filtrar tras recorrerla. Cada hito que añada un listado lo crea con la tabla (`create_tenant_table` + índice).
- **`has_more` sin contar:** se piden `limit + 1` filas. Con exactamente `limit` filas no hay página vacía de más.
- **Cursor opaco y FIRMADO:** `{ id }` firmado con `ActiveSupport::MessageVerifier` (clave derivada de `secret_key_base`, propósito `cursor`, URL-safe). Un cursor manipulado, inventado o de otro propósito → `400 pagination.invalid_cursor`. Está firmado, **no cifrado**: el cliente no debe interpretarlo, pero no es un secreto.
- **`limit`:** entero entre 1 y 100 (50 por defecto). Fuera de rango o no entero → `400 pagination.invalid_limit` (se rechaza, no se recorta en silencio).
- El orden del scope recibido se **descarta** (`reorder` por id); sus filtros se conservan. Un recurso que necesite otro orden (p. ej. citas por `starts_at`) extiende el cursor con ese hito, no con `OFFSET`.
- Pendiente de uso real: el endpoint de ejemplo es de un solo registro; el primer listado (M1) usa `render_page`. La API está cubierta por `spec/services/api/pagination/cursor_spec.rb` y `spec/requests/api/pagination_spec.rb` (con una sonda de test, que no existe en la aplicación).

## Serialización con Alba (M0.06)

- `Api::Serializer` (base, incluye `Alba::Resource`) y **un serializer por representación** en `app/serializers/<pack>/` (`Tenancy::OrganizationSerializer`). Lo que no se lista no sale.
- Fechas: tipo registrado `:iso8601` (`attributes created_at: :iso8601`) → UTC con `Z` y milisegundos.
- El contrato lo vigila doble: el spec de rswag valida cada respuesta real contra el esquema (`required` + `additionalProperties: false`, escritos a mano porque el modo estricto de rswag vuelve obligatorios los campos opcionales como `detail`), así que un campo de más o de menos en el serializer rompe ese spec; y el check de drift exige que `openapi/v1.yaml` coincida con lo que generan los specs.

## Idempotencia (M0.11)

> Código: pack `platform/idempotency` (`backend/packs/platform/idempotency`). Concern `Idempotency::Idempotent`.

```
idempotency_keys
  organization_id, principal_key, key, request_fingerprint (SHA-256 de método + ruta + cuerpo), response_status,
  response_body, response_headers (jsonb: Location), content_type, expires_at (24 h), created_at, updated_at
  UNIQUE (organization_id, principal_key, key)
```

```ruby
class AppointmentsController < Api::BaseController
  around_action :in_organization            # abre Tenancy.with_context (M0.08)
  include Idempotency::Idempotent
  idempotent :create, required: true        # declarar DESPUÉS del filtro que abre el contexto
end
```

- Misma clave y mismo fingerprint → NO se ejecuta la acción: se devuelve la respuesta guardada (estado, cuerpo, `Content-Type`, `Location`) con `Idempotency-Replayed: true`.
- Misma clave y distinto fingerprint (otro cuerpo, **otra ruta u otro método**) → `409 idempotency.key_reused` (el cuerpo guardado no se revela).
- Sin header: la acción corre normal, salvo `required: true` → `400 idempotency.key_required`. Clave inválida (vacía, > 255 caracteres, fuera de ASCII imprimible) → `400 idempotency.key_invalid`.
- **Solo las respuestas 2xx se guardan.** Un error (422, excepción) libera la clave: el cliente puede corregir y reintentar con la misma. Las filas vencidas (24 h) se ignoran y se reemplazan al reutilizar la clave.
- **Desvío de la forma original (`UNIQUE (organization_id, key)`):** la unicidad incluye al principal (`principal_key` = `user:<uuid>`, `api_key:<uuid>`... o `anonymous` para la reserva pública). Con la clave global por organización, el segundo usuario que eligiera la misma clave recibiría la **respuesta guardada del primero** (fuga). Una sola columna de texto y no `(type, id)`, porque un `UNIQUE` no trata los `NULL` como iguales y el anónimo no tiene id. La reserva pública anónima comparte alcance dentro de la organización: la protege la entropía de la clave (UUID); añadir IP o slug al alcance si hiciera falta (M2).
- **Concurrencia (dos peticiones simultáneas con la misma clave):** la reserva (INSERT de la fila) y la acción corren en la **misma transacción** (se une a la del contexto). La segunda petición choca en el índice único y **espera** a que la primera confirme o revierta: si confirma, lee la fila y repite la respuesta; si revierte, la reserva desaparece y la segunda se ejecuta. Nunca corren dos acciones con la misma clave, y la clave y el recurso nacen o desaparecen juntos. Coste: la segunda petición queda bloqueada lo que dure la primera (acotado por `statement_timeout`).
- Requiere un contexto de tenancy abierto y, si la acción es autenticada, `Current.principal`. Sin contexto lanza `Idempotency::MissingContext` (bug, `500`).
- **Contrato:** `components.parameters.IdempotencyKey` / `IdempotencyKeyRequired` y `components.responses.IdempotencyKeyReused` / `IdempotencyKeyInvalid` (en `spec/swagger_helper.rb`); cada endpoint idempotente los referencia con `$ref` (los endpoints de creación llegan en M1; hoy no hay ninguno real, y el concern se prueba con una sonda que crea empresas: `spec/support/idempotency_probes.rb`).
- **Pendiente:** purga masiva de filas vencidas (el índice `expires_at` ya existe); `reminder_dispatches` con clave única (ADR-0022) llega con notificaciones.

## Generación del contrato y del cliente TypeScript

```
specs de rswag (spec/api, packs/*/spec/api) ──bin/rails openapi:generate──▶ backend/openapi/v1.yaml
        └─ componentes: spec/swagger_helper.rb + packs/*/spec/openapi_components.rb          │
                                                                          pnpm api:generate (openapi-typescript)
                                                                                              ▼
                                                              frontend/packages/api-client/src/schema.d.ts
                                                              + openapi-fetch (cliente tipado) + ApiError + unwrap
                                                              + hooks de TanStack Query (M0.12, sobre `unwrap`)
```

- **Un spec de rswag por endpoint** (en `spec/api/` o `packs/<capa>/<pack>/spec/api/`): cada `response` declara su esquema y `run_test!` ejecuta la petición real y valida el cuerpo. Los errores usan `$ref` a los componentes reutilizables **`Problem`**, **`ValidationProblem`** (con `errors[]` de **`FieldError`**) y `PageInfo` (definidos en `spec/swagger_helper.rb`); cada pack aporta los suyos (`Organization`, `Company`, `Branch`) en `spec/openapi_components.rb`.
- **Generación determinista** (`lib/openapi/`): el formateador `Openapi::Formatter` (subclase del de rswag) escribe el documento con **claves ordenadas en todos los niveles**, sin símbolos YAML y sin ajuste de línea (el plegado de Psych no debe decidir si hay drift). Además corrige que rswag declara `produces` por operación y lo copia a todas las respuestas: se deja `application/json` en los éxitos y `application/problem+json` en los errores (≥ 400), para que el cliente no reciba uniones absurdas. `bin/rails openapi:generate` corre el formateador en modo `--dry-run` (no ejecuta peticiones) y exige el entorno test; lo hace solo.
- **Versiones fijadas:** rswag 2.17.0, alba 4.0.3, OpenAPI 3.0.3 (no 3.1: rswag valida con `json-schema`, que no entiende `type: [x, "null"]`), openapi-typescript 7.13.0, openapi-fetch 0.17.0.
- **`pnpm api:generate`** (desde `frontend/`) regenera `schema.d.ts` desde `backend/openapi/v1.yaml`. En Docker el contrato se monta de solo lectura en `/app/backend/openapi`. `bin/api-generate` regenera **ambos** pasos dentro de Docker.
- **TypeScript 6.0.3 en `packages/api-client`**: openapi-typescript usa la API programática de TypeScript (`ts.factory`), que TS 7 (compilador nativo) no expone; se comporta igual que el pin de `packages/config` (ver [10](10-infrastructure.md)). Volver a una sola versión cuando openapi-typescript soporte TS 7.
- El cliente (`createApiClient`) envía `credentials: "include"`. El backend ya exige `X-CSRF-Token` en las mutaciones (M0.07, [11](11-security.md#csrf-panel)); **el envío automático desde el cliente (y recuperar el token con `GET /auth/session` al arrancar) llega con M0.12**.
- **`ApiError { status, code, title, errors[], requestId, detail, type, instance }`:** `unwrap(client.GET(...))` devuelve el cuerpo de éxito (tipado por el contrato) o lanza `ApiError`. Una respuesta que no es problem+json (un 502 del proxy) también es `ApiError` con `code: "http.<status>"`. `unwrap` es el `queryFn` natural de TanStack Query.
- **Check de drift** (`infra/scripts/check-api-contract.sh`, etapa `api-contract` de `bin/ci`, job `api-contract` de CI y check requerido en `branch-protection.sh`): regenera contrato y cliente, y falla si alguno difiere de lo versionado (compara contra una copia previa, no contra el índice de git, así funciona con cambios sin commitear). Sus casos están en `check-api-contract_test.sh`. Además, `spec/api/openapi_contract_spec.rb` falla si alguna ruta `/api/v1` no está documentada en `v1.yaml` (principio 3).
- **Criterio 5 (campo inexistente → `tsc` falla):** `test/type-safety.test.ts` ejecuta `tsc` de verdad sobre dos fixtures (el campo existente compila; `phone_number` falla con `TS2339`), y `test/types.typecheck.ts` lo deja permanente en `pnpm typecheck` con `@ts-expect-error` ("verde cuando falla"): si el cliente dejara de tipar, el error esperado desaparece y `tsc` falla con "Unused '@ts-expect-error'".

## Documentación

- **Swagger UI** en `/api/docs` y el contrato en `/api/docs/v1.yaml` (rswag-ui / rswag-api), solo en **desarrollo, test y staging**: `Api::Docs.enabled?` (verdadero en development/test, o con `API_DOCS_ENABLED=true`, que es como staging —`RAILS_ENV=production`— lo activa). En producción las rutas no existen.
- En producción, solo la documentación pública para integradores (cuando existan).

## Endpoints de organización, empresa y sucursal (M0.08)

Solo lectura, en el pack `platform/access` (`Api::V1::Access::*`, rutas en `packs/platform/access/config/routes/access.rb`): `GET /api/v1/organizations`, `GET /api/v1/organizations/:id`, `GET .../organizations/:organization_id/companies[/:id]` y `GET .../companies/:company_id/branches[/:id]`. Los listados usan `render_page` (paginación por cursor) y **solo devuelven lo que el principal puede leer**; `GET /organizations` devuelve un resumen (`OrganizationSummary`: `id`, `name`, `status`). Códigos: `401 auth.unauthenticated`, `404 resource.not_found` (no existe o no es visible para el principal: indistinguibles), `403 access.forbidden` (visible, pero la policy lo niega) y `403 access.organization_suspended`. El endpoint de ejemplo de M0.06 dejó de estar bajo el flag `open_organization_endpoint`, que se **eliminó**. Reglas completas en [04](04-access-control.md#del-request-al-recurso).

## Autenticación en la API (M0.07)

- `Api::BaseController` incluye `Api::Authentication`: **deny by default**. Un controlador que hereda de él sin hacer nada exige sesión; para ser público declara `skip_authentication!` (con un comentario del porqué) **y** se añade a la allowlist de `spec/requests/api/authentication_spec.rb`. Ese spec recorre todas las rutas del router sin sesión y exige `401`.
- Las mutaciones (`POST`/`PUT`/`PATCH`/`DELETE`) con sesión exigen `X-CSRF-Token` (el `csrf_token` de `POST /auth/login` o `GET /auth/session`) y, si llega `Origin`, que sea el propio. Detalle y razones en [11](11-security.md#csrf-panel).
- Endpoints `auth` documentados en el contrato con el esquema de seguridad `cookieAuth` (`apiKey` en cookie) y el parámetro de cabecera `X-CSRF-Token`. En los specs de rswag, el login es el real (`sign_in`, `spec/support/authentication_helpers.rb`): la cookie viaja por el jar de la sesión de integración, no se simula.
- `Current.session` (`Identity::CurrentSession`) y `Current.principal` (`Identity::Principal::User`) quedan fijados en las acciones autenticadas.

## Cómo agregar un endpoint

1. Controlador `Api::V1::<Pack>::XController < Api::BaseController` en el pack (exige sesión **y autorización** por defecto: cada acción debe llamar a `authorize` y cada `index` a `policy_scope`, o falla en test; si el recurso cuelga de `organizations/:organization_id/...` el contexto se resuelve y valida solo; una acción que no autoriza declara `skip_authorization!(reason:)`; solo si DEBE ser público, `skip_authentication!` comentado y en la allowlist del spec; ver más abajo), con su archivo de rutas en el pack (`packs/<capa>/<pack>/config/routes/<pack>.rb`, montado con `draw(:<pack>)` bajo `/api/v1` en `config/routes.rb`).
2. Un serializer por representación (`Api::Serializer`); listados con `render_page`.
3. Errores de dominio nuevos: `Api::ErrorRegistry.register` en el initializer del pack + título en su locale.
4. Spec de rswag en `spec/api/` del pack (200 y los errores con `$ref` a `Problem`/`ValidationProblem`; `security [ { cookieAuth: [] } ]`, `sign_in` y, en mutaciones, el parámetro `X-CSRF-Token`); esquemas nuevos en `spec/openapi_components.rb` del pack.
5. `bin/api-generate` y versionar `backend/openapi/v1.yaml` y `schema.d.ts`. Si lo olvidas, `bin/ci api-contract` (y CI) fallan.
