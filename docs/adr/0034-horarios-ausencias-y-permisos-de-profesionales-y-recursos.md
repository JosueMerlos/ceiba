# ADR-0034: Horarios por defecto solo al activar, permisos de profesionales y recursos, ausencias con motivo libre y dueño explícito

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-11 |
| Origen | Plan del hito [M1.02](../milestones/F1-citas-dominio/M1.02-profesionales-recursos-y-horarios.md): tres decisiones abiertas que el desarrollador resolvió antes de implementar y dos decisiones delegadas (D1 y D7) que cambian la forma del modelo y de la API pública de `access` |

## Contexto

- Al activar `appointments` hay que darle a cada sucursal un horario con el que arrancar ([M1.02](../milestones/F1-citas-dominio/M1.02-profesionales-recursos-y-horarios.md)). El hook `on_enable` corre al activar el módulo, pero `Tenancy::AddBranch` no publica ningún evento: una sucursal creada después no pasa por ningún hook.
- La matriz de [04-access-control](../architecture/04-access-control.md) decía "ver", "asignar" o "las propias" sin claves de permiso, dejaba ambigüedades (¿el `professional` edita su horario?, ¿qué ve cada rol de los profesionales?) y no tenía fila para los recursos.
- Una ausencia es un hecho de la persona en la empresa (`time_offs` no tiene sucursal), pero se gestiona desde una sucursal. Su motivo puede revelar datos de salud ("cirugía", "incapacidad") y lo vería la recepción; las notas de cita ya prohíben datos clínicos ([domain/appointments](../domain/appointments.md)).
- `weekly_schedules` y `time_offs` pertenecen a un profesional, a un recurso o (los horarios) a la sucursal. Un `owner_id` polimórfico no admite clave foránea, y [domain/appointments](../domain/appointments.md) exige claves compuestas hacia los padres.
- El `user_id` que vincula a un profesional con una persona es un id de usuario, que es global: sin verificación se podría vincular a cualquier usuario del sistema.

## Decisión

1. **Las sucursales creadas después de activar el módulo NO reciben horario por defecto; una sucursal sin horario está cerrada.** `Appointments::Lifecycle::OnEnable` da lunes a sábado de 08:00 a 18:00 a cada sucursal de la empresa que no tenga horario de sucursal, es idempotente (desactivar y reactivar no pisa un horario editado ni duplica) y se audita (`schedule.defaults_created`). Cubre solo las sucursales que existen al activar. El motor de disponibilidad trata una sucursal sin franjas como cerrada, que es el fallo seguro. Se revisa en [M2.01](../milestones/F2-agenda-interna/M2.01-panel-de-catalogos.md): tras crear una sucursal, el panel lleva al gerente a configurar su horario.
2. **Permisos, claves y concesiones** (el manifiesto del módulo y la [matriz](../architecture/04-access-control.md) dicen lo mismo):

   | Clave | company_manager | branch_manager | receptionist | professional |
   | --- | --- | --- | --- | --- |
   | `appointments.professional.read` (`from_descendants`) | ✅ | ✅ | ✅ | — |
   | `appointments.professional.manage` (crear, editar, archivar, servicios que presta) | ✅ | — | — | — |
   | `appointments.professional.assign` (a una sucursal) | ✅ | ✅ su sucursal | — | — |
   | `appointments.professional.read_own` (su perfil, en la sucursal donde está asignado) | — | — | — | ✅ |
   | `appointments.resource.read` | ✅ | ✅ | ✅ | ✅ |
   | `appointments.resource.manage` | ✅ | ✅ | — | — |
   | `appointments.schedule.read` | ✅ | ✅ | ✅ | — |
   | `appointments.schedule.manage` | ✅ | ✅ | — | — |
   | `appointments.schedule.read_own` | — | — | — | ✅ |
   | `appointments.time_off.read` | ✅ | ✅ | ✅ | — |
   | `appointments.time_off.manage` | ✅ | ✅ | — | — |
   | `appointments.time_off.manage_own` (ver, crear y borrar las propias) | — | — | — | ✅ |

   Los requisitos de recurso de un servicio se gestionan con `appointments.service.manage`. Las reglas que se desprenden:
   - **"Lo propio" se evalúa en la ruta de la sucursal**, nunca por rol: el registro del profesional tiene `user_id` igual al del usuario **y** está asignado a la sucursal de la ruta. `read_own` y `manage_own` no son `from_descendants` (el validador del manifiesto lo rechaza), así que solo se pueden preguntar en la sucursal; por eso el perfil propio se lee por `GET branches/:branch_id/professionals/:professional_id`.
   - El `professional` **ve** su horario semanal pero no lo edita (no existe `schedule.manage_own`) y **gestiona** sus ausencias.
   - `branch_manager` y `receptionist` leen todos los profesionales de la empresa (nombre, sucursales y servicios, sin PII de identidad).
   - **El `branch_manager` gestiona las ausencias de los profesionales asignados a SU sucursal.** Como la ausencia es de la persona y no de la sucursal, bloquea su agenda también en las otras sucursales donde atienda; se acepta porque la ausencia es un hecho de la persona y el alcance del `branch_manager` se limita a los asignados a la suya.
3. **`time_offs.reason` es texto libre opcional de hasta 200 caracteres, sin datos de salud.** Está en `filter_parameters` (no llega a logs ni a Sentry), la auditoría de la ausencia es **por id e intervalo** y nunca incluye el motivo, y la documentación pide no escribir datos clínicos en él. Es la misma higiene que las notas del cliente ([ADR-0033](0033-autorizacion-y-pii-de-clientes-y-servicios.md)).
4. **Dueño explícito en vez de `owner_id` polimórfico (D1).** `weekly_schedules` y `time_offs` tienen las columnas `professional_id` y `resource_id` (anulables), `owner_type` y un CHECK de coherencia (solo la columna del tipo de dueño está llena). Cada columna lleva su clave foránea compuesta: el profesional solo tiene horario en una sucursal donde está asignado y el recurso solo en la suya. Precedente: `memberships`. El modelo expone predicados (`professional_owner?`) para que las políticas no comparen cadenas ni citen roles.
5. **La pertenencia del usuario vinculado se verifica con `Access.member?(user_id:, organization_id:)` (D7).** Es una lectura nueva en el archivo público existente `access.rb`; no cambia el modelo de autorización ni la lista de API pública de `access`.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| 1B. Evento `platform.branch_created.v1` en `AddBranch` y suscripción del módulo que crea el horario por defecto | Comportamiento uniforme | Toca `platform/tenancy` y el outbox (fuera del alcance del hito); asincronía: la sucursal existe un momento sin horario |
| 1C. Tratar una sucursal sin horario como abierta de 08:00 a 18:00 | Nada que configurar | Reserva sobre una sucursal que nadie ha configurado; un horario implícito que no se ve ni se audita |
| 2B. Además, `schedule.manage_own` para el profesional | Más autonomía | Más permiso del que pide el hito; el horario de la sucursal depende del negocio, no de cada profesional |
| 2C. Que solo el `company_manager` gestione ausencias de profesionales con varias sucursales | Una ausencia no bloquea otra sucursal sin el visto bueno de la empresa | Más reglas en la política y el gerente de sucursal pierde una tarea diaria |
| 3B. `kind` cerrado (vacaciones, personal, capacitación, otro) sin texto libre | Sin riesgo de datos sensibles | Menos expresivo |
| 3C. Sin motivo | Mínimo | La recepción no sabe por qué |
| 4B. `owner_type` + `owner_id` polimórfico | Una sola columna | Sin clave foránea: la integridad entre tenants y la de "asignado a la sucursal" quedarían en la aplicación |
| 5B. `Access::MembershipDirectory` | Existe | Es privado y cruza tenants |

## Consecuencias

- **Positivas:** la BD garantiza que un profesional solo tiene horario donde está asignado y que un recurso solo lo tiene en su sucursal; el fallo seguro de una sucursal sin horario es "cerrada"; la autorización de lo propio no depende de nombres de rol; el motivo de una ausencia no se propaga a ningún registro técnico.
- **Negativas / costos aceptados:** una sucursal nueva no aparece en la reserva hasta que alguien le configura el horario. Una ausencia gestionada desde una sucursal afecta a todas las sucursales de la persona. La confianza en que nadie escriba datos de salud en el motivo depende de la disciplina del usuario. Dos columnas de dueño anulables en lugar de una.
- **Qué obliga a hacer:** M2.01 debe guiar al gerente a configurar el horario tras crear una sucursal; el motor de disponibilidad (M1.03) debe leer "sin franjas" como cerrada; el despliegue corre `access:sync` para persistir los permisos nuevos; toda política nueva sobre un dueño pregunta por predicados del modelo y nunca cita un rol (cop `Ceiba/AccessPolicyRoles`).

## Cuándo revisarla

- En M2.01, al construir la creación de sucursales: si la guía del panel no basta (sucursales sin horario en producción), reabrir la opción 1B (evento al crear sucursal).
- Si el `professional` pide editar su propio horario semanal (`schedule.manage_own`).
- Si una ausencia de una persona con varias sucursales genera conflictos entre gerentes.
