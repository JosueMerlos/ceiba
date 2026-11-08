# ADR-0022: Auditoría append-only e idempotencia de escrituras

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 (ampliada 2026-11-07) |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §4; `plans/plan-ecosistema-modular-seguridad.md` §2.2 |

## Decisión

- `audit_events(organization_id, actor_type, actor_id, action, auditable_type, auditable_id, before, after, metadata, created_at)`, append-only, **garantizado por un trigger** que rechaza UPDATE y DELETE (no solo por convención). Cubre negocio **y** eventos de autenticación.
- `Idempotency-Key` genérico (`idempotency_keys` único por organización y clave, con fingerprint del request) en la creación de citas y en los envíos de recordatorios (`reminder_dispatches` con clave única).

## Consecuencias

- **Positivas:** trazabilidad confiable; reintentos y dobles clics seguros.
- **Negativas:** la tabla crece indefinidamente (particionado por fecha cuando haga falta).
- **Obliga a:** M0.11.

## Cuándo revisarla

Cuando `audit_events` supere un tamaño que afecte el rendimiento: particionar por mes.
