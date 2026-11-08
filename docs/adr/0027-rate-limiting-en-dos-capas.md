# ADR-0027: Rate limiting en dos capas (Rack::Attack + rate_limit de Rails)

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-seguridad.md` §4 (corregido) |

## Contexto

El plan ponía Rack::Attack "primero en la cadena" pero con claves `user_id` y `api_key_id`, que no existen antes de autenticar sin consultar la BD.

## Decisión

- **Capa 1, Rack::Attack** (store Redis, namespace `ratelimit:`): reglas por IP, IP + slug y email del login. Frena a anónimos sin tocar la BD.
- **Capa 2, `rate_limit` de Rails 8** en controladores: cuotas por `user_id` y `api_key_id`, después de autenticar.
- Límites configurables por ENV; `429` con `Retry-After` y cabeceras `RateLimit-*`; proxies de confianza verificados.

## Consecuencias

- **Positivas:** cada capa usa la información que realmente tiene; sin consultas a la BD en el middleware.
- **Obliga a:** M0.13 (base) y M4.02 (tabla completa); el test de NAT.

## Cuándo revisarla

Si se añade un WAF o CDN que asuma la capa 1.
