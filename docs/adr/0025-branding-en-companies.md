# ADR-0025: Branding como columnas y adjuntos en companies

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-pendientes.md` §1.8 (decisiones 1–4) |

## Decisión

- Campos en `companies`: `brand_name`, `tagline`, `primary_color`, `secondary_color`, `accent_color`, `font_choice` (1 de 3 curadas), y logo, banner y favicon con ActiveStorage. El historial lo guarda `audit_events`.
- Editan `company_manager` y `org_admin`.
- URL pública `/c/:slug` en el dominio de la plataforma; dominio propio como upsell (P3).
- Sin tipografía custom; PNG, JPG o WebP, **sin SVG** en el MVP; validación de contraste ≥ 4.5:1 con fallback.
- Correos con nombre de remitente y logo de la empresa, desde el dominio de la plataforma.

## Consecuencias

- **Positivas:** simple; suficiente para el MVP.
- **Obliga a:** M2.04.

## Cuándo revisarla

Si el branding se vuelve un producto (temas, versiones): tabla separada.
