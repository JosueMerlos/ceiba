# ADR-0024: Mercado objetivo inicial: solo Nicaragua

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos (los planes citaban la LFPDPPP de México) |

## Decisión

- Normativa: **Ley 787** y Decreto 36-2012 ([13-privacy-ley-787](../architecture/13-privacy-ley-787.md)), sustituyendo las referencias a la LFPDPPP.
- Zona horaria por defecto `America/Managua`; aun así todo se guarda en UTC y se prueba el DST.
- Moneda **por empresa**: `NIO` o `USD`.
- Teléfonos E.164 con región por defecto `NI`.
- WhatsApp como canal principal.
- Locale `es-NI`, con i18n preparado desde el día 1.

## Consecuencias

- **Positivas:** foco; requisitos concretos.
- **Negativas:** el cobro de la suscripción depende de pasarelas disponibles en Nicaragua (riesgo a investigar antes de F6).
- **Obliga a:** revisión legal antes de los pilotos.

## Cuándo revisarla

Al decidir la expansión a otro país: nueva normativa, monedas y proveedores.
