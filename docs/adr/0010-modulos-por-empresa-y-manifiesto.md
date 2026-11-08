# ADR-0010: Módulos activados por empresa y descritos por un manifiesto

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 (manifiesto añadido 2026-11-07) |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3; sesión de cimientos |

## Contexto

El ecosistema debe aceptar módulos nuevos fácilmente y permitir módulos distintos por negocio. Sin un contrato, agregar un módulo implica cablear a mano permisos, rutas, menús, settings y eventos.

## Decisión

- `company_modules(company_id, module_key, enabled_at, disabled_at, settings JSONB)`, con un índice único `(company_id, module_key)`. Se activa por **empresa**, nunca por organización.
- Cada módulo declara un **manifiesto** (permisos, scopes de API, JSON Schema de settings con niveles, eventos publicados y suscritos, navegación, `requires`, hooks `on_enable` y `on_disable`) que un registro valida al arrancar.
- Se separan **entitlement** (lo que permite el plan), **activación** (`company_modules`) y **feature flag** (Flipper).
- Un módulo inactivo devuelve `404` en la API, no recibe eventos y no aparece en `/me`.

## Consecuencias

- **Positivas:** un módulo nuevo se declara; la plataforma no cambia.
- **Negativas:** el registro y su validación son código de plataforma que hay que mantener.
- **Obliga a:** M0.09; el [playbook de módulos](../playbooks/add-a-module.md); la suite de cobertura de módulos.

## Cuándo revisarla

Si un módulo necesita activarse por sucursal (hoy, `settings_levels` cubre los overrides por sucursal).
