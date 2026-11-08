# ADR-0017: Sesiones en BD con autenticación propia (base: generador de Rails 8), sin Devise

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-seguridad.md` §2.1 y §8 |

## Contexto

Una cookie firmada no se puede revocar desde el servidor. Devise reparte controladores y convenciones por toda la app y encaja mal con los packs.

## Decisión

Tabla `sessions` en `platform/identity`, partiendo del generador de autenticación de Rails 8 (`has_secure_password` + `Session` en BD) y adaptándolo: multi-organización, 2FA, bloqueo progresivo, HIBP y auditoría.

## Consecuencias

- **Positivas:** "cerrar todas las sesiones" es posible; el código es pequeño y propio, dentro de un pack.
- **Negativas:** funciones que Devise da hechas (confirmación, desbloqueo) se escriben a mano.
- **Obliga a:** M0.07 y M4.02.

## Cuándo revisarla

Si se necesita SSO u OAuth con terceros: se evalúa OmniAuth sobre esta base.
