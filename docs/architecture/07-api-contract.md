# 07 — Contrato API

> Decisiones: [ADR-0012](../adr/0012-contrato-openapi-y-cliente-generado.md), [ADR-0016](../adr/0016-credenciales-por-superficie.md). Hito: M0.06 (y cada hito que agrega endpoints).

## Principios

1. **El contrato es un artefacto versionado**: `backend/openapi/v1.yaml`, generado a partir de los specs de rswag y commiteado.
2. **El frontend nunca escribe tipos a mano** para respuestas de la API: los genera desde el contrato.
3. **CI falla si el contrato y el cliente generado divergen**, o si un endpoint no está documentado.

## Superficies

| Prefijo | Consumidor | Credencial |
| --- | --- | --- |
| `/api/v1/...` | Panel (SPA) e integradores | Cookie de sesión **o** API key (`Authorization: Bearer`) |
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
  "type": "https://docs.<dominio>/errors/slot-unavailable",
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

## Idempotencia

```
idempotency_keys
  organization_id, key, request_fingerprint (hash de método + ruta + body), response_status, response_body,
  created_at, expires_at (24 h)
  UNIQUE (organization_id, key)
```

- Misma clave y mismo fingerprint → se devuelve la respuesta guardada.
- Misma clave y distinto fingerprint → `409`.
- Implementada como concern genérico en `platform` (M0.11) y aplicada por endpoint.

## Generación del cliente TypeScript

```
rswag specs → openapi/v1.yaml → openapi-typescript → packages/api-client/src/schema.d.ts
                                                  → openapi-fetch (cliente tipado)
                                                  → hooks de TanStack Query por recurso
```

- `pnpm api:generate` regenera; CI ejecuta la generación y falla si hay diff.
- El cliente envía `credentials: "include"` y el token CSRF en las mutaciones ([11](11-security.md)).
- El cliente traduce un `problem+json` a un error tipado `ApiError { status, code, errors }`.

## Documentación

- Swagger UI / Redoc disponible en desarrollo y staging, en `/api/docs`.
- En producción, solo la documentación pública para integradores (cuando existan).
