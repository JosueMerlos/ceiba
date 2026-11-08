# ADR-0026: Facturación a la organización por sucursal activa

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-pendientes.md` §3.2 y §5 (decisiones 10–11) |

## Decisión

Suscripción mensual facturada a la **organización** (una factura consolidada), con cantidad = sucursales activas de todas sus empresas. Prorrateo al dar de alta; las bajas se recalculan en el ciclo siguiente, sin reembolsos. Piloto: 3 meses gratis a cambio de un acuerdo de datos y uso diario. Los planes definen **entitlements** ([05](../architecture/05-module-system.md)).

## Consecuencias

- **Negativas / riesgo:** disponibilidad de pasarelas para comercios nicaragüenses **sin verificar**; plan B: cobro manual registrado.
- **Obliga a:** investigar en F6 antes de implementar.

## Cuándo revisarla

Con los datos de los pilotos (disposición a pagar, tamaño típico).
