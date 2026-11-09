# ADR-0022: Auditoría append-only e idempotencia de escrituras

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 (ampliada 2026-11-07 y 2026-11-09) |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §4; `plans/plan-ecosistema-modular-seguridad.md` §2.2 |

## Decisión

- `audit_events(organization_id, actor_type, actor_id, action, auditable_type, auditable_id, before, after, metadata, created_at)`, append-only, **garantizado por un trigger** que rechaza UPDATE y DELETE (no solo por convención). Cubre negocio **y** eventos de autenticación.
- `Idempotency-Key` genérico (`idempotency_keys` único por organización y clave, con fingerprint del request) en la creación de citas y en los envíos de recordatorios (`reminder_dispatches` con clave única).

## Ampliación (M0.11, 2026-11-09)

- **Los eventos de autenticación van a una tabla global hermana**, `auth_audit_events(action, user_id, request_id, ip, user_agent, metadata, created_at)`, no a `audit_events`. Motivo: `users` y `sessions` son globales (ADR-0028) y un login fallido con un correo sin cuenta no tiene organización; una `organization_id` NULL en `audit_events` rompería el guardián de tablas tenant, la FK y, con RLS (M4.03), exigiría una política que expusiera esos eventos a todos los tenants. Mismo trigger append-only. Los eventos de seguridad que sí pertenezcan a una organización (roles, invitaciones) irán a `audit_events`.
- **El trigger es de sentencia y cubre también `TRUNCATE`.**
- **`idempotency_keys` es único por `(organization_id, principal_key, key)`**, no solo por organización y clave: evita que un principal reciba la respuesta guardada de otro. Pack propio `platform/idempotency`.

## Consecuencias

- **Positivas:** trazabilidad confiable; reintentos y dobles clics seguros.
- **Negativas:** la tabla crece indefinidamente (particionado por fecha cuando haga falta).
- **Obliga a:** M0.11.

## Cuándo revisarla

Cuando `audit_events` supere un tamaño que afecte el rendimiento: particionar por mes.
