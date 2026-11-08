# ADR-0011: El giro del negocio no es un módulo

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3 |

## Contexto

Clínicas, salones y barberías parecen productos distintos. La tentación es crear "citas dentales" y "citas de salón".

## Decisión

El giro (`companies.business_type`) es **configuración**. Un salón y una clínica comparten el **mismo** pack `appointments`; cambian sus servicios, su branding, sus settings y los módulos adicionales que tengan activos.

## Consecuencias

- **Positivas:** un solo motor de disponibilidad y sin duplicación.
- **Negativas:** las diferencias por vertical se expresan con settings o con campos específicos (F5+), no con código ramificado por giro.
- **Obliga a:** prohibir `if business_type == ...` en la lógica de dominio; usar settings.

## Cuándo revisarla

Si un vertical exige un flujo de agenda radicalmente distinto; en ese caso sería un módulo nuevo, no una rama.
