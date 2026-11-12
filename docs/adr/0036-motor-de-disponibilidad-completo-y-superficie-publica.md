# ADR-0036: Motor de disponibilidad completo (servicios, buffers, `:any`, recursos) y su superficie pública anónima

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-12 |
| Origen | Plan del hito [M1.04](../milestones/F1-citas-dominio/M1.04-disponibilidad-completa.md): nueve decisiones abiertas que el desarrollador resolvió antes de implementar y diez delegadas por convención. Extiende [ADR-0035](0035-motor-de-disponibilidad-caso-base.md) y concreta [ADR-0029](0029-citas-multi-servicio.md) |

## Contexto

- [ADR-0029](0029-citas-multi-servicio.md) decidió que una cita agrupa varios servicios y que el motor calcula sobre el total, pero no fijó cómo se suman los buffers. El dominio decía "buffer previo del primero + buffer posterior del último", y el criterio 1 del hito ("corte (+10 después) + barba" = bloque de 60) solo cuadraba sumando todos los buffers.
- `service_resource_requirements` admite varios tipos de recurso por servicio, pero una cita tiene un solo `resource_id` y una sola exclusion constraint de recurso ([domain/appointments](../domain/appointments.md#restricciones-críticas)).
- Los recursos tienen franjas semanales opcionales ([ADR-0034](0034-horarios-ausencias-y-permisos-de-profesionales-y-recursos.md)); no estaba decidido qué significa un recurso sin franjas.
- M1.03 dejó `appointments` sin `resource_id`: sin la columna, el motor no puede restar la ocupación de un recurso por citas.
- La superficie `/api/public/v1/c/:slug` ([07-api-contract](../architecture/07-api-contract.md#superficies)) es anónima: no hay sesión ni contexto de tenant, y `Tenancy::Company` es una tabla tenant con `require_tenant`, así que resolver un slug es una lectura entre organizaciones.
- El endpoint del panel publicado en M1.03 recibía un solo `service_id`.

## Decisión

1. **Buffers en los bordes.** Duración (`duration_minutes`) = Σ duraciones (con override de sucursal). Bloque = buffer previo del **primer** servicio + duración + buffer posterior del **último**: son preparación y limpieza de la cita, no de cada servicio. El criterio 1 del hito se corrigió a "barba + corte". Precio = Σ precios (con override), en la moneda de la empresa.
2. **El bloque entero cabe en el horario.** Con buffers, el bloque `[inicio − previo, fin + posterior)` debe caber en el horario de la sucursal ∩ el del profesional (y, si hace falta, en el tiempo libre de un recurso). La rejilla sigue sobre el inicio del servicio: con apertura a las 09:00, buffer previo de 10 y paso de 15, el primer inicio es 09:15. **El bloque nunca empieza en el pasado:** la anticipación mínima se mide sobre el inicio del servicio (lo que ve el cliente) y, además, `inicio − previo >= ahora`; con anticipación 0 y buffer previo de 10, ningún hueco empieza antes de `ahora + 10 min`.
3. **`appointments.resource_id` llega en este hito**, anulable, con clave foránea compuesta a `resources` (creada `NOT VALID` y validada en otra migración) y dos índices concurrentes (el de la FK y el de lectura del motor, parcial sobre las citas que bloquean). La exclusion constraint `no_overlap_resource` sigue en M1.05 con `Book`.
4. **Un tipo de recurso por petición.** Si la combinación de servicios pide más de un tipo, `422` con `service_ids` `multiple_resource_kinds`. El recurso asignado es el primer compatible libre por `id`.
5. **Un recurso sin franjas propias sigue el horario de la sucursal**; si tiene franjas, lo restringen. A diferencia del profesional (sin franjas = sin huecos), una silla o una sala no tienen turno.
6. **`:any` con `least_busy`:** para cada inicio, entre los profesionales elegibles libres (asignados a la sucursal, activos y que prestan **todos** los servicios), el de menos citas que bloquean cuyo `starts_at` cae en el día local de la sucursal, en todas sus sucursales; desempate por `id`. Sin elegibles, la lista sale vacía (`200`).
7. **Búsqueda pública por slug:** `Tenancy::PublicDirectory.company_by_slug` es el único lector anónimo entre organizaciones y está en `AllowedFiles` de `Ceiba/TenantBypass`. Al activar RLS (M4.03) se cubre con una función `SECURITY DEFINER` o con el rol privilegiado.
8. **Superficie pública:** `GET /api/public/v1/c/:slug/availability?branch_id&service_ids&professional_id&from&to` expone `starts_at`, `ends_at`, `professional_id`, `resource_id` y el precio, sin datos personales ni ids de citas. Exige la organización activa (una suspendida es una puerta cerrada, como en el panel), el módulo activo, la empresa activa, `public_booking_enabled` en la empresa **y** en la sucursal (se leen por separado porque la mezcla deja que la sucursal pise a la empresa) y la sucursal activa. Las puertas de empresa (slug, organización, empresa, módulo y `public_booking_enabled` de la empresa) se evalúan **antes** de leer la forma de la consulta; así una consulta mal formada no distingue una empresa cerrada de un slug desconocido, y solo las de sucursal (que necesitan `branch_id`) van después. Todo lo que no aplica (slug, módulo, puerta, sucursal, servicio o profesional) responde el **mismo** `404 resource.not_found`; solo el rango da `422`. Rango de hasta 14 días. La ocupación en sucursales hermanas resta igual que en el panel: un anónimo puede deducir **que** un profesional está ocupado, nunca el porqué.
9. **Caché de 30 s** del cuerpo `200`, después de las puertas (desactivar la reserva pública surte efecto inmediato), con una clave que lleva `company_id` y un SHA-256 de los parámetros normalizados. En producción, `redis_cache_store` con timeouts cortos y fallo abierto.
10. **Regla 5 de Rack::Attack** (disponibilidad pública, IP + slug, 60 / 1 min) en este hito, porque el endpoint anónimo sale con él.
11. **Contrato del panel:** `service_id` se reemplaza por `service_ids` (separados por comas, en orden de ejecución, de 1 a 5 y sin repetir) y `professional_id` admite `any`. Era un cambio incompatible sin consumidores. La respuesta añade `professional_id` y `resource_id` por hueco, y `meta.price` (`{ amount_minor, currency }`) y los buffers.
12. **Índices de ausencias** `(organization_id, professional_id, ends_at)` y `(organization_id, resource_id, ends_at)`, parciales por dueño, creados de forma concurrente en su propia migración y retirando los de `starts_at` en otra. strong_migrations no admite índices no únicos de más de 3 columnas, así que `company_id` queda como filtro.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Sumar los buffers de todos los servicios | El criterio 1 original cuadra en cualquier orden | Bloques más largos que la realidad; contradice el dominio |
| Buffers fuera del horario | Aprovecha la primera y la última franja | Dos reglas distintas; preparación fuera del turno |
| Diferir `resource_id` a M1.05 | No toca `appointments` | M1.05 reabre el cargador y el núcleo |
| Un recurso por tipo (`resource_ids`) | Modela "sala + equipo" | Tabla `appointment_resources` y otra constraint |
| Recurso sin franjas = cerrado | Mismo fallo seguro que la sucursal | Todo recurso nuevo bloquea los servicios que lo piden |
| Función `SECURITY DEFINER` ya para el slug | Lista para RLS | SQL crudo y un rol que hoy no hace falta |
| Mantener `service_id` y añadir `service_ids` | Aditivo | Dos formas de pedir lo mismo para siempre |
| Dejar la regla 5 para M3.02 | Respeta el reparto anterior | Un endpoint anónimo y costoso sin límite propio |

## Consecuencias

- **Positivas:** el motor cumple el contrato completo de ADR-0029 y lo que ofrece coincide con lo que la base aceptará también para los recursos; el número de consultas sigue fijo por forma de petición (con o sin recurso requerido, profesional concreto o `:any`), sea cual sea el número de días, profesionales o servicios; las ausencias se leen sin recorrer el historial.
- **Negativas / costos aceptados:** una combinación que pide dos tipos de recurso no se puede reservar; se pierde el primer o el último hueco del día cuando hay buffers; un anónimo ve libre/ocupado de los profesionales (como cualquier página de reservas); un camino privilegiado más que M4.03 debe cubrir.
- **Qué obliga a hacer:** M1.05 añade `no_overlap_resource` sobre la columna que ya existe; `Book` (M1.05) usa el mismo `ensure_eligible!` con `services:`; M3.02 consume el endpoint público tal cual (con su caché de 30 s, `Book` revalida); quien cambie la política de reparto actualiza el oráculo de `invariants_spec`.

## Cuándo revisarla

- Si un negocio necesita "sala + equipo" en una misma cita: tabla `appointment_resources`.
- Si los pilotos piden aprovechar los bordes del horario con buffers.
- Si aparece abuso de la disponibilidad pública que la regla 5 no contiene, o si exponer `professional_id` a anónimos se vuelve un problema.
- Al activar RLS (M4.03): la búsqueda por slug.
