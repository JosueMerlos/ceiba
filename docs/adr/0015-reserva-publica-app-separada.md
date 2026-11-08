# ADR-0015: La reserva pública es una app React ligera separada

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Inconsistencia en `plans/`: "server-rendered" (seguridad §5) vs SPA React |

## Contexto

La página `/c/:slug` llega desde Instagram y WhatsApp a móviles con conexiones lentas. El panel es una SPA pesada.

## Decisión

`frontend/apps/booking`: app React independiente, con su propio bundle (JS crítico < 150 KB gzip), que comparte tokens, primitivas, branding y api-client con el panel. Se sirve en el mismo origen.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Rails server-rendered + Hotwire | Muy ligera, buen SEO | Dos stacks de UI; el branding se implementa dos veces |
| Rutas dentro del panel | Lo más simple | Arrastra el bundle del panel; incumple el presupuesto móvil |

## Consecuencias

- **Positivas:** un solo stack de UI y un presupuesto de rendimiento controlable.
- **Negativas:** SEO limitado (aceptable: el tráfico llega por enlace directo).
- **Obliga a:** un presupuesto verificado en CI (tamaño del bundle) y CSP estricta.

## Cuándo revisarla

Si el SEO orgánico se vuelve un canal relevante: prerender o SSR de la página de entrada.
