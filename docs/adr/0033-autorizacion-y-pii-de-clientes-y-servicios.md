# ADR-0033: Autorización desde la sucursal, PII del cliente en su propio recurso y overrides por cambio efectivo

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-10 |
| Origen | Plan del hito [M1.01](../milestones/F1-citas-dominio/M1.01-clientes-y-servicios.md): seis decisiones abiertas que el desarrollador resolvió antes de implementar, más la revisión independiente del plan |

## Contexto

- El cliente es un registro **de empresa** ([ADR-0021](0021-cliente-unico-por-empresa.md)), pero lo crean y editan `branch_manager` y `receptionist`, que solo tienen membership de **sucursal**. El motor de acceso resuelve hacia abajo (un permiso de empresa cubre sus sucursales) y solo lee hacia arriba (`from_descendants`, únicamente en lecturas); "leer hacia arriba nunca da escritura" es un invariante explícito ([04-access-control](../architecture/04-access-control.md)).
- Los servicios son también de empresa, y los roles de sucursal necesitan leer el catálogo con el que trabajan. El DSL del manifiesto de módulos no admitía `from_descendants`.
- La regla de [calidad de código](../harness/calidad-de-codigo.md) saca la PII y los campos cifrados de las respuestas, pero el staff necesita ver el teléfono del cliente para llamarlo o escribirle.
- El índice único `(company_id, phone_e164)` incluye a los clientes archivados: un archivado que vuelve con el mismo teléfono choca con él.
- Un override de sucursal puede tocar la duración (permitida al `branch_manager`) y el precio (solo `company_manager`), y un `PUT` parcial o un `DELETE` podrían borrar sin permiso un valor que otro rol fijó.

## Decisión

1. **Los recursos de empresa que escribe el staff de sucursal se autorizan en la sucursal desde la que se actúa.** Las rutas llevan la sucursal (`/organizations/:o/companies/:c/branches/:b/customers`); la política consulta el permiso en el alcance de esa sucursal y el `company_manager` pasa por la regla hacia abajo. El recurso sigue siendo de la empresa (la lista muestra todos sus clientes). El motor no cambia y el invariante "leer hacia arriba nunca da escritura" se mantiene.
2. **El DSL del manifiesto de módulos acepta `from_descendants:` en permisos de LECTURA.** `appointments.service.read` lo usa para que los roles de sucursal lean el catálogo de la empresa. El validador del manifiesto rechaza la marca en acciones que no son de lectura, igual que el registro de permisos, y cualquier valor que no sea exactamente `true` o `false`.
3. **Excepción de PII acotada.** Solo los endpoints del recurso cliente devuelven teléfono, correo y notas, y solo a quien tiene `platform.customer.read`. Ningún otro endpoint, log, mensaje de error ni evento de auditoría los incluye: la auditoría del cliente es **por id** (qué campos cambiaron, no sus valores), porque `full_name` va en claro; además `full_name` y `name_prefix` (la búsqueda por nombre del listado) están en `filter_parameters`, así que no llegan a logs ni a Sentry. El `professional` no tiene acceso a clientes hasta que existan las citas que definan el alcance "los de sus citas".
4. **Un cliente archivado con el mismo teléfono se restaura, no se duplica.** `FindOrCreate` y el alta del staff lo desarchivan, toman el nombre de la petición y auditan `customer.restored`. Se conserva un cliente por teléfono y por empresa, con su mismo id (historial). El correo y las notas se **limpian** salvo que la petición los envíe: el número pudo pasar a otra persona y no debe heredar sus datos. `FindOrCreate` sobre un cliente activo lo devuelve intacto.
   Un cliente archivado **no admite ediciones**: `PATCH` responde `422 validation.failed` con `base: archived` (la autorización se evalúa antes, así que quien no puede editar recibe `403`). Restaurar con el alta es la única vía de vuelta.
5. **Los overrides se autorizan por cambio efectivo y el `PUT` es un merge.** Poner, cambiar o quitar un precio exige `appointments.service.override_price`; lo mismo con la duración y `appointments.service.override_duration`. Un cambio mixto no autorizado responde `403` para toda la petición y no se aplica nada. El `PUT` cambia solo los atributos presentes; un `null` explícito borra ese valor. La autorización corre contra la fila actual, bloqueada para la escritura.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| 1B. Extender el motor con escritura hacia arriba para claves marcadas | Rutas solo de empresa, más simples | Rompe un invariante explícito del motor y toca la autorización de plataforma |
| 2B. Que los roles de sucursal lean el catálogo solo por una ruta de sucursal | No toca el DSL | Duplica rutas de lectura; el catálogo efectivo es más propio de M1.04 |
| 3B. Lectura de todos los clientes de la empresa para el `professional` | Simple | Da más acceso del que dice la matriz |
| 4B. Aplicar la duración e ignorar el precio en un cambio mixto | Más permisivo | Silencia un intento no autorizado; respuesta ambigua |
| 5B. Teléfono enmascarado y valor completo en un endpoint aparte que audita la lectura | Máxima minimización | Más superficie y complejidad para un caso de uso diario |
| 4C. Conservar el correo y las notas del archivado al restaurar | Menos fricción al volver | Un número reasignado heredaría datos personales de otra persona |
| 4D. Permitir editar un cliente archivado (o desarchivar con `PATCH`) | Menos errores 422 | Dos caminos para volver y datos que cambian sin que el cliente esté activo |
| 6B. Índice único parcial `WHERE archived_at IS NULL` | El archivado queda congelado | Dos registros para la misma persona e historial partido; contradice "único por empresa" |

## Consecuencias

- **Positivas:** el motor de acceso y su invariante quedan intactos; la PII sale por un solo recurso y el resto del sistema sigue sin ella; un cliente sigue siendo uno por teléfono; un rol no puede borrar valores que no le corresponde cambiar.
- **Negativas / costos aceptados:** la URL del cliente lleva una sucursal aunque el recurso sea de empresa, y una empresa sin sucursales no puede gestionar clientes (sin sucursal tampoco hay citas). Un alta "nueva" puede devolver un registro viejo. La regla de PII tiene una excepción escrita que hay que mantener acotada. El DSL de módulos crece una opción.
- **Qué obliga a hacer:** el serializer de clientes es el único que expone teléfono, correo y notas; los tests de aislamiento y de matriz cubren las rutas por sucursal; el manifiesto de cada módulo declara `from_descendants` solo en lecturas; toda escritura de cliente audita por id; el despliegue corre `access:sync` para persistir los permisos nuevos.

## Cuándo revisarla

- Cuando existan las citas (M1.05) y el `professional` deba ver "los clientes de sus citas".
- Si aparece un recurso de empresa que el staff de sucursal deba escribir sin una ruta de sucursal natural (por ejemplo, una API pública o una importación), o si un segundo recurso necesita devolver PII.
