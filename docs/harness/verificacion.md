# Reglas de verificación para agentes

> Adaptado de `ticket-harness/core/rules/verification.md`. Comandos concretos en [`AGENTS.md`](../../AGENTS.md) y
> [`harness.config.md`](../../harness.config.md). Todo corre dentro de Docker (`make up` antes).

## Qué correr

- Por defecto, comprobaciones enfocadas en el entorno de Compose. La paridad completa con CI (`make ci`) solo antes de un push
  o cuando se pide.
- Corre: la prueba del rojo, los tests afectados y la cobertura de consumidores o regresión adyacente.
- Amplía cuando cambias: contratos compartidos (OpenAPI, `packages/api-client`, la API pública de un pack), autorización o
  tenancy, factories / `spec/support` / helpers, o algo con gran radio de impacto. Las suites de plataforma (aislamiento de
  tenant, matriz de autorización, cobertura de módulos, contrato, eventos) son obligatorias si tocas su área.
- Corre la suite completa antes de merges grandes, no tras cada edición. Reporta la cobertura que de verdad ejecutaste.
- Cada comprobación va contra las ediciones FINALES. Editar tras un verde lo invalida (incluido el autocorrect de RuboCop o
  Prettier y las pasadas de limpieza).
- Lint de los archivos tocados; `pnpm typecheck` (`tsc --noEmit`) para TypeScript tocado; si tocas un endpoint o un
  serializer, `bin/api-generate` y revisa que el diff del contrato sea el esperado; si tocas el bundle de una app, la etapa
  `frontend-bundle` (presupuestos de [`bundle-budgets.json`](../../frontend/bundle-budgets.json)).
- Cada fase de un plan corre, antes de entregarse, las etapas que puede romper, no solo sus specs: si toca seeds o datos
  demo, `make ci s=e2e` (los E2E se apoyan en esos fixtures); si toca migraciones, `make ci s=backend-migrations`; si toca
  packs o dependencias entre ellos, `make ci s=backend-packs`; si toca endpoints, `make ci s=api-contract`.

## Antes de un push autorizado

`make ci` (los mismos pasos que CI: lint, Packwerk, migraciones, tests, seguridad, contrato, bundle, E2E) y reporta el
resultado por etapa. Para repetir una etapa: `make ci s=<etapa>`.

## Los cambios de UI necesitan evidencia renderizada

- Para cambios visuales, renderiza e inspecciona los estados afectados en escritorio y en 360 px (panel y booking son
  responsive; booking es móvil primero).
- Para interacciones, ejercita el comportamiento e inspecciona el DOM o el árbol de accesibilidad, no solo una captura.
- Acompaña las capturas con aserciones concretas; reporta errores de consola y peticiones fallidas.
- Entra siempre por el proxy, `http://localhost:8080` (mismo origen, [ADR-0013](../adr/0013-monorepo-y-mismo-origen.md)).
- Un servicio que no está `healthy`, un Vite sin estilos o una base no preparada es un bloqueo que se reporta, no una razón
  para saltarse la comprobación (ver la tabla de problemas del [`README`](../../README.md#solución-de-problemas)).

## Un criterio de aceptación no está verificado hasta probarlo

Cada criterio del hito se mapea a una prueba (test, comando, captura con aserción) y se clasifica como: probado, fallando,
falta, o pendiente manual (despliegue, datos de producción). Uno fallando o faltante detiene la ejecución. Nunca se corre nada
contra una base compartida o de producción para probar un criterio.

## Reporte

Reporta: el resultado; las comprobaciones exactas y su resultado decisivo; limitaciones y lo no verificado; y el estado de
entrega (local, commit, push, merge, despliegue). Detente cuando el resultado pedido y sus comprobaciones estén completos, o
cuando un bloqueo o una aprobación necesiten al desarrollador.

## Fallos del entorno

- "Migraciones pendientes" en la suite: `make migrate` y, si persiste, `make db-prepare`; reintenta UNA vez. Si vuelve a
  fallar por lo mismo, detente y repórtalo. Recuerda que `structure.sql` está versionado: no lo reescribas como efecto colateral.
- Antes de reintentar la suite completa, confirma que no hay otro proceso de test activo. Si la corrida enfocada y la completa
  no coinciden, investiga el aislamiento antes de cambiar aserciones.
- **Un solo dueño de la base de test a la vez.** Los agentes no corren suites en segundo plano ni dos suites en paralelo
  (comparten `ceiba_test` y se pisan: fallos transitorios que no son del código). Los revisores no corren suites: leen código
  o usan `bin/rails runner` en `RAILS_ENV=test` con los cambios dentro de una transacción que se revierte.
- **Tras borrar o renombrar un inicializador o un archivo de configuración**, reinicia el backend antes de verificar
  (`docker compose restart api worker`): el proceso de desarrollo conserva los bloqueos `to_prepare` viejos y, por ejemplo,
  responde 500 donde debía responder 401. Si el E2E falla en la primera pantalla con la suite de backend en verde, comprueba
  primero `curl -s -o /dev/null -w '%{http_code}' localhost:8080/api/v1/me` (debe dar 401).
- Borra los scripts temporales al terminar.
