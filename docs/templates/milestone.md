# M<fase>.<nn> — <Título corto en imperativo o sustantivo>

| Campo | Valor |
| --- | --- |
| Estado | `pendiente` · `en curso` · `bloqueado` · `terminado` |
| Fase | F<n> — <nombre de la fase> |
| Estimación | <n> h (máximo 15 h; si excede, dividir el hito) |
| Depende de | [M0.xx](../F0-cimientos/M0.xx-....md) |
| Desbloquea | M0.yy, M1.zz |
| Docs relacionados | [arquitectura](../../architecture/...) · [ADR-00nn](../../adr/...) |

## Objetivo

Una o dos frases que describan un **resultado observable**, no una actividad.
Mal: "Configurar Packwerk". Bien: "CI rechaza cualquier PR en el que un pack use una constante privada de otro".

## Contexto

- Por qué este hito existe y por qué **ahora** (qué bloquea si no se hace).
- Qué decisiones previas lo condicionan (enlazar ADRs).
- Qué problema real evita (incidente, riesgo, deuda).

## Alcance

**Incluye**

- …

**No incluye** (y dónde se resuelve)

- … → M?.??

## Diseño

Decisiones concretas que este hito materializa: tablas, interfaces, nombres, archivos clave.
No repetir la arquitectura: enlazarla y bajar solo lo necesario para ejecutar.

## Tareas

Ordenadas en ciclo TDD (rojo → verde → refactor). Cada tarea cabe en una sesión de 1–3 h.

- [ ] Escribir spec que falle para …
- [ ] Implementar …
- [ ] Refactor / documentación …

## Criterios de aceptación

Verificables por cualquiera, sin interpretación. Formato Dado / Cuando / Entonces.

1. **Dado** …, **cuando** …, **entonces** ….

## Definición de terminado

- [ ] Todos los criterios de aceptación pasan y tienen un test automatizado (o un paso manual documentado si no es automatizable).
- [ ] CI en verde (lint, tests, Packwerk, seguridad).
- [ ] Docs de arquitectura actualizados si el diseño cambió; ADR nuevo si se tomó una decisión.
- [ ] Demo breve (captura, GIF o comando reproducible) registrada en la sección "Notas de cierre".
- [ ] Estado actualizado en [`roadmap/README.md`](../../roadmap/README.md).

## Riesgos y notas

| Riesgo | Mitigación |
| --- | --- |
| … | … |

## Notas de cierre

_Se completa al terminar: qué cambió respecto al plan, qué se aprendió, deuda abierta._
