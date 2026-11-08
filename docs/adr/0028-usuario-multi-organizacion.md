# ADR-0028: Un usuario puede pertenecer a varias organizaciones

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-pendientes.md` §3.1 (decisión 9) |

## Decisión

`users` es global (no tenant); la pertenencia la dan los `memberships` (tenant). Al entrar, si hay más de una organización, el usuario elige el contexto; `Current.context` se construye tras esa elección y se valida contra sus memberships. Cambiar de contexto no requiere volver a iniciar sesión, pero invalida las cachés del frontend.

## Consecuencias

- **Positivas:** habilita el caso persona/profesional y a contadores o consultores con varios clientes.
- **Negativas:** `users` queda fuera de RLS; su lectura se limita por los memberships.
- **Obliga a:** un E2E de cambio de contexto sin fugas.

## Cuándo revisarla

No se prevé.
