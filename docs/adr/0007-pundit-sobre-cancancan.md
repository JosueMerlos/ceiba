# ADR-0007: Pundit (no CanCanCan) para la autorización

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-seguridad.md` §3 |

## Contexto

En un monolito modular, la autorización debe ser tan modular como el código.

## Decisión

**Pundit**, con una policy por modelo **dentro de su pack** y una `Access::BasePolicy` que niega por defecto.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| CanCanCan | Popular, DSL compacto | Un `Ability` central que cruza todos los packs: un god object, justo lo que Packwerk busca evitar |
| ActionPolicy | Scoping, caché y composición superiores | Pundit es suficiente; cambiar no compra nada hoy |

## Consecuencias

- **Positivas:** policies junto a su pack; specs simples; `policy_scope` nativo.
- **Obliga a:** `verify_authorized` y `verify_policy_scoped` en todos los controladores.

## Cuándo revisarla

Si la composición de permisos o el caché se vuelven un problema medible; la alternativa natural es ActionPolicy.
