# Reglas de testing para agentes

> Adaptado de `ticket-harness/core/rules/testing.md`. La estrategia del proyecto (pirámide, las seis suites de plataforma,
> factories, E2E) está en [`12-testing-strategy`](../architecture/12-testing-strategy.md); estas reglas cubren CÓMO escribe
> tests un agente.

## Primero el rojo (TDD estricto)

- Antes de un cambio de comportamiento: escribe el test, CÓRRELO y míralo fallar por la razón esperada. Después implementa y
  vuelve a correrlo. Vale para bugs, guardas, migraciones, rellenos y valores por defecto de flags.
- Un test que pasa a la primera no prueba nada: corrige el test (no ejercita el hueco).
- Exentos: refactors puros cubiertos por tests existentes, formato, documentación, recompilación de assets.
- Si no se puede ejecutar (Docker caído, base no preparada), dilo claramente. Nunca afirmes un ciclo rojo/verde que no corriste.
- El comportamiento que solo existe en el navegador necesita un E2E de Playwright (`frontend/e2e`, `make e2e`) o un smoke de
  la skill `ui-qa`.
- En commits, el rojo va en un commit `test(...)` que cita el fallo (`(rojo: ...)`) y el verde en el `feat`/`fix` siguiente.

## Las eliminaciones son borrados

Cuando se elimina una ruta, acción, página, job, flag o permiso: borra su código y los tests que lo ejercitaban, y no agregues
nada. Nada de "ahora responde 404", ni aserciones de "no puede hacer X" para una capacidad eliminada, ni aserciones convertidas
en su negación. Primero-el-rojo no aplica a un borrado. Toda línea añadida en un diff de borrado necesita una razón explícita.

## No debilites el test para ponerlo en verde

- Trata los reportes de bug y los hallazgos de revisión como afirmaciones a reproducir o falsear antes de editar.
- Mantén visibles los fallos. Nunca debilites una aserción, mockees el comportamiento bajo prueba ni cambies entradas para pasar.
- Si una corrida enfocada y una completa no coinciden, es un problema de aislamiento o de entorno: investígalo antes de tocar
  aserciones (ejemplo real: el estado global de `Current`/`LogContext`/tenant que contagiaba al spec siguiente con `--seed 5718`).

## Aserciones fuertes

- Deriva lo esperado independientemente de la implementación (del hito, del ADR o del cálculo a mano), no copiando la salida.
- Afirma el resultado observable (estado, valor de retorno, filas persistidas, evento en el outbox, respuesta `problem+json`),
  no que se llamó a un método.
- Cubre el borde y el camino no feliz: vacío, nil, cero, uno, muchos, máximo, duplicado, otro dueño, **otra organización**,
  vencido, concurrente.
- Prueba una implementación plausible pero errónea: ¿qué bug seguiría pasando este test? Agrega el caso que lo mata.
- Mínimo por unidad nueva de lógica: 3 casos, al menos 1 adversarial.

## Fija las guardas que quedaron inalcanzables

Cuando una restricción nueva (NOT NULL, índice único, CHECK, FK compuesta, política RLS) vuelve imposible de alcanzar una rama
defensiva, el test que la probaba ya no se puede construir y la guarda sobrevive a mutaciones.

- No borres sin más el test imposible: reemplázalo por uno que fije la restricción (la escritura levanta el error esperado) y
  otro que fije la expresión guardada.
- Fija la expresión capturando el SQL generado (`ActiveSupport::Notifications.subscribe("sql.active_record")`), no stubeando
  la conexión.
- Fija TODAS las expresiones de la guarda; muta cada una por separado y confirma que cada mutación pone el test en rojo.

## Fixtures, factories y tiempo

- Persiste solo cuando el comportamiento consulta, recarga, valida, muta o destruye el registro; si no, `build` /
  `build_stubbed`.
- Las factories derivan `organization_id` del padre y los specs que tocan modelos tenant usan `with_tenant(org) { ... }`
  (`spec/support/tenancy_helpers.rb`). Ver [`12`](../architecture/12-testing-strategy.md#factories).
- Congela el tiempo (`travel_to` / `freeze_time`). Nunca dependas del reloj ni de la zona de la máquina; prueba con zonas con
  DST aunque Nicaragua no lo use.
- Sin ids fijos, sin mocks globales que se filtren entre tests, sin estado mutable creado en `before(:all)`.
- Procesos de test concurrentes necesitan bases, claves y puertos distintos. Antes de reintentar la suite completa, confirma
  que no hay otro proceso de test corriendo.

## Política de mocks

- Mockea solo fronteras externas reales (red, pasarelas, WhatsApp, reloj). En frontend, la API se simula con MSW, no
  mockeando hooks ni el cliente generado.
- Nunca mockees la unidad bajo prueba ni sus colaboradores del mismo pack.
- Para validar terceros, credenciales sandbox; nunca producción.
