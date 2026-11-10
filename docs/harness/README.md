# Reglas para agentes de IA

Reglas de trabajo para agentes (Claude Code, OpenCode) adaptadas a ceiba desde ticket-harness (checkout local en `~/projects/ticket-harness`).
El punto de entrada es [`AGENTS.md`](../../AGENTS.md) en la raíz, que ambos agentes leen de forma nativa.

| Documento | Contenido |
| --- | --- |
| [`seguridad.md`](seguridad.md) | Entornos, secretos, tiempo, tenancy, dinero y efectos externos, contrato de la API, migraciones |
| [`testing.md`](testing.md) | TDD estricto, borrados, aserciones fuertes, guardas inalcanzables, factories, mocks |
| [`verificacion.md`](verificacion.md) | Qué correr, antes de un push, evidencia de UI, criterios de aceptación, reporte |
| [`calidad-de-codigo.md`](calidad-de-codigo.md) | Alcance, barrido de llamadas, comentarios, autocorrect, eliminar código |
| [`rails.md`](rails.md) | Comandos en Docker, migraciones, RuboCop y cops `Ceiba/*`, RSpec, Packwerk |

## Relación con el resto de `docs/`

Estas reglas dicen **cómo trabaja un agente**; no deciden arquitectura. Si una regla de aquí contradice un documento de
`docs/architecture/` o un ADR, gana el documento de arquitectura y esta regla se corrige.

## Mantenimiento

Son copias adaptadas, no enlaces: un cambio en el harness no llega solo. Al actualizar el harness, compara
`core/rules/*.md` y `profiles/rails/rules.md` con estas copias y trae lo que aplique, manteniendo los overrides de ceiba
(docs, planes y commits en español con comentarios de código en inglés, conventional commits, comandos en Docker).
