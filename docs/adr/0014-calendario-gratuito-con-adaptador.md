# ADR-0014: Agenda con librería gratuita detrás del componente AgendaView

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos (verificación de licencia de FullCalendar) |

## Contexto

El plan elegía FullCalendar. La vista con profesionales o recursos en columnas (resource-timegrid) es **Premium**, con licencia comercial desde unos 480 USD. El core gratuito no la incluye.

## Decisión

Solo librerías gratuitas. La página habla con un componente propio `AgendaView` (contrato en [08-frontend](../architecture/08-frontend.md)); la librería concreta vive en un adaptador. Candidata principal: react-big-calendar (vista por recursos gratuita), que se evalúa en M2.02. Plan B: una vista diaria por recursos propia.

## Consecuencias

- **Positivas:** sin costo de licencia antes de tener ingresos; reemplazable.
- **Negativas:** posiblemente menos pulido que FullCalendar Premium; el adaptador es código extra.
- **Obliga a:** criterios de selección documentados en M2.02.

## Cuándo revisarla

Con ingresos, si la UX de la agenda frena la adopción: el adaptador permite cambiar a una opción de pago.
