# ADR-0004: Jerarquía Organización → Empresa → Sucursal

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3; `plans/plan-ecosistema-modular-pendientes.md` §6 |

## Contexto

El plan original solo tenía Organización → Sucursal. Un grupo con una clínica y un salón mezclaba catálogos, clientes y marcas.

## Decisión

Organización (contrato, plan, administración global) → **Empresa** (giro, marca, moneda, catálogo, profesionales, clientes, módulos activos) → Sucursal (zona horaria, horarios, recursos, agenda). Los servicios viven en la empresa; la sucursal solo sobrescribe duración o precio. La zona horaria vive solo en la sucursal.

Un negocio pequeño es 1·1·1, y la interfaz colapsa los niveles.

## Consecuencias

- **Positivas:** soporta independientes y franquicias con el mismo modelo.
- **Negativas:** más joins y contexto; la UI debe ocultar niveles cuando no aportan.
- **Obliga a:** `company_id` obligatorio en servicios, profesionales, clientes y citas; `branch_id` obligatorio en citas.

## Cuándo revisarla

Si aparece un nivel real intermedio (p. ej. regiones) con reglas propias.
