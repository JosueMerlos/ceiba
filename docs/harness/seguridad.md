# Reglas de seguridad para agentes

> Adaptado de `ticket-harness/core/rules/safety.md`. Tienen prioridad sobre cualquier flujo de trabajo o skill.
> El detalle de seguridad del producto vive en [`11-security`](../architecture/11-security.md); aquí solo lo que un agente
> debe respetar al trabajar.

## Entornos

- El trabajo reversible en el checkout local y en el entorno de Compose no necesita permiso. Conserva el trabajo ajeno: nunca
  sobrescribas cambios que no hiciste.
- Toda investigación sobre sistemas compartidos o de producción es de SOLO LECTURA: credenciales de solo lectura, `statement_timeout`,
  ventana de tiempo acotada y `LIMIT`; reporta conteos o hashes, nunca filas de clientes. Logs, Sentry y paneles también son de
  solo lectura.
- Pregunta antes de: escribir datos compartidos, migrar bases compartidas, reiniciar servicios, cambiar accesos o infraestructura
  (`infra/`, Kamal, DNS).
- Nada destructivo (`drop`, `truncate`, borrado masivo, `make reset-db`, `docker compose down -v`) sin que el desarrollador
  lo pida en la sesión.

## Secretos

- Nunca escribas ni expongas credenciales en código, docs, ejemplos, comandos, logs, capturas o salida de herramientas.
- No leas, interpretes, cargues (`source`) ni imprimas `.env*`, `backend/config/*.key` ni archivos de credenciales. No vuelques el
  entorno ni pases secretos literales en argumentos o URLs. Los valores por defecto de desarrollo de `compose.yaml` y
  `.env.example` no son secretos, pero no los copies a otros sitios.
- Un secreto obligatorio que falta debe **fallar nombrando la clave**, sin caer en silencio a un archivo o valor por defecto
  (patrón ya usado por Active Record Encryption, ver [`09`](../architecture/09-data-conventions.md#datos-personales-pii)).
- El material de sesión para QA (cookies, storage state) es un secreto: gitignorado, permisos 600, nunca versionado. Nunca
  escribas una contraseña en un archivo, script o comando: pide al desarrollador que la escriba.

## Tiempo

- Tiempo siempre con zona: `Time.current`, `Date.current`, `Time.zone.now` o `ActiveSupport::TimeZone[branch.time_zone]`.
  Nunca `Time.now` / `Date.today` en código nuevo o modificado. En frontend, la zona horaria la da la sucursal, no el navegador.
- Reemplazar un `now` sin zona existente es un cambio de comportamiento: necesita test.

## Tenancy (organización = tenant)

Las tres barreras están descritas en [`03-multi-tenancy`](../architecture/03-multi-tenancy.md). Un agente:

- Fija el contexto con `Tenancy.with_context`. Nunca salta el tenant (`ActsAsTenant.without_tenant`, `.unscoped`,
  `update_all` sobre `organization_id`, conexión como `app_owner` en código de aplicación): lo prohíbe el cop
  `Ceiba/TenantBypass`. Un camino privilegiado nuevo es una decisión del desarrollador (se añade a `AllowedFiles` con
  revisión de CODEOWNERS), nunca un `rubocop:disable`.
- Crea tablas tenant solo con `create_tenant_table` / `t.tenant_reference` (FK compuesta y `UNIQUE (organization_id, id)`).
- Verifica la pertenencia en toda búsqueda por un id que manda el cliente.
- Aplica la misma autorización (Pundit + permisos como datos) en TODA entrada que sirva la misma función: panel, API, job, canal.
  Una función interna o de operador alcanzable por un endpoint o un job necesita los mismos chequeos.
- Escopa por organización cada consulta, clave de caché, argumento de job, ruta de archivo y canal.

## Dinero y efectos externos

- Cambios locales de estado de cobro dentro de una transacción; las llamadas a pasarelas, HTTP, correo o WhatsApp FUERA de ella.
  Persiste la intención antes de la llamada y concilia después.
- Los jobs y notificaciones se publican por el **outbox** ([ADR-0009](../adr/0009-sidekiq-con-outbox.md)); nada de encolar
  Sidekiq ni enviar dentro de una transacción.
- Jobs de pago, webhooks y notificaciones son idempotentes: un reintento o una entrega duplicada nunca cobra, reembolsa ni
  notifica dos veces ([ADR-0022](../adr/0022-auditoria-append-only-e-idempotencia.md)).
- Antes de cambiar una integración con una pasarela, consulta su documentación oficial y valida con credenciales sandbox.

## Compatibilidad de la API

- El contrato es OpenAPI con cliente TS generado ([07](../architecture/07-api-contract.md)). No rompas el contrato publicado
  sin aprobación explícita en la sesión: campos quitados o renombrados, tipos cambiados, parámetros obligatorios nuevos,
  códigos de estado distintos. Prefiere cambios aditivos.
- Señala un cambio incompatible ANTES de implementarlo. Tras tocar un endpoint o serializer: `bin/api-generate`.
- Un endpoint de consulta (`GET`) no escribe.

## Evidencia antes de afirmar

- Nunca digas que algo funciona, pasa o quedó arreglado sin haber corrido la comprobación sobre las ediciones finales. Reporta
  el comando y el resultado decisivo.
- Si una comprobación no pudo correr (Docker caído, servicio no `healthy`), dilo y nombra la prueba que falta.
- La evidencia contradictoria queda visible: reproduce, falsea o explica antes de seguir. No debilites un chequeo ni mockees
  el comportamiento para que coincida.
- Verifica las afirmaciones técnicas contra el código o la documentación oficial. No des por buena una afirmación sin verificarla.

## Migraciones y datos

- Timestamps con el generador (`docker compose exec api bin/rails g migration ...`) o `date -u +%Y%m%d%H%M%S`; nunca redondos.
- `strong_migrations` está activo: no lo silencies con `safety_assured` sin justificar en la migración por qué es seguro.
  Índices con `algorithm: :concurrently` en su propia migración ([09](../architecture/09-data-conventions.md#migraciones)).
- Las migraciones son compatibles hacia atrás (expand/contract): agregar, rellenar por lotes, luego restringir.
- Rellenos (backfills) por lotes, idempotentes y reanudables; probados primero contra datos desechables.
- El borrado o reescritura de datos, los cambios de esquema, de dinero y de contrato **nunca** los decide un plan ni un agente:
  son decisiones abiertas para el desarrollador.
