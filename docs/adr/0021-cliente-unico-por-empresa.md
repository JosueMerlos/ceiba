# ADR-0021: El cliente final es único por empresa y vive en platform/customers

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 (pack definido 2026-11-07) |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3; sesión de cimientos |

## Decisión

El cliente se identifica por empresa (en la práctica, por teléfono E.164 dentro de la empresa) y **no** se comparte entre empresas del grupo (privacidad y giros distintos). Vive en el pack de plataforma `customers`, porque todos los módulos futuros lo usan. Los reportes consolidados solo agregan conteos.

## Consecuencias

- **Positivas:** privacidad por diseño; los módulos futuros no dependen de citas para tener clientes.
- **Negativas:** la misma persona aparece como dos clientes en dos empresas del grupo (es intencional).
- **Obliga a:** `UNIQUE (company_id, phone_e164)`; escrituras solo vía `Customers::*`.

## Cuándo revisarla

Si un grupo requiere un programa de lealtad compartido entre empresas: se haría con consentimiento explícito y vinculación, no fusionando clientes.
