# ADR-0016: Credenciales por superficie; sin JWT hasta que exista una app móvil

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-seguridad.md` §1 |

## Contexto

API-first suele confundirse con "JWT para todo". Cada superficie tiene riesgos distintos.

## Decisión

- Panel: cookie de sesión `httpOnly` respaldada en BD, con CSRF.
- Integraciones: API key opaca, revocable, con scopes por módulo.
- Cliente final: token firmado de un uso.
- Webhooks: HMAC.
- Back-office: sesión separada de `PlatformStaff` + 2FA.
- JWT corto + refresh rotativo **solo** cuando exista una app móvil.

Todas convergen en un `Access::Principal` evaluado por el mismo Pundit.

## Consecuencias

- **Positivas:** revocación inmediata; el XSS no roba la sesión.
- **Negativas:** varios mecanismos que mantener.
- **Obliga a:** [11-security](../architecture/11-security.md).

## Cuándo revisarla

Cuando se construya una app móvil.
