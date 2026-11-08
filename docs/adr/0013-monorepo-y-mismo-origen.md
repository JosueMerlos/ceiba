# ADR-0013: Monorepo y un solo origen HTTP

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos |

## Contexto

Hay un backend, dos apps de frontend y paquetes compartidos. Las sesiones por cookie `httpOnly` y CSRF se complican con orígenes cruzados (CORS, `SameSite`, credenciales).

## Decisión

Un **monorepo** (`backend/`, `frontend/` con pnpm workspace, `infra/`, `docs/`). Un **solo origen**: un proxy enruta `/api` → Rails, `/c/*` → booking y `/` → panel, **igual en desarrollo y en producción**.

## Consecuencias

- **Positivas:** sin CORS; un cambio de contrato y su consumidor viajan en el mismo commit; las cookies y el CSRF se comportan igual en todos los entornos.
- **Negativas:** el CI del monorepo debe filtrar por rutas para no correr todo siempre (optimización posterior).
- **Obliga a:** un proxy en desarrollo (M0.01) y una estrategia de estáticos en producción (M4.04).

## Cuándo revisarla

Si aparece un frontend en otro dominio (p. ej. un dominio propio por empresa, P3): se evalúa CORS explícito o un proxy por dominio.
