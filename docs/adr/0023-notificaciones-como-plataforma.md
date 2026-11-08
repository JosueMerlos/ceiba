# ADR-0023: Las notificaciones son una capacidad de plataforma

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos (corrección: los recordatorios estaban dentro de `appointments`) |

## Decisión

Pack `platform/notifications`: canales (correo, WhatsApp Cloud API) tras una interfaz común, plantillas con la marca de la empresa, **verificación de consentimiento** antes de cada envío (Ley 787), delivery log e idempotencia. Los módulos solo piden `Notifications.deliver(template:, customer:, data:, idempotency_key:)`. Los recordatorios de citas los programa `appointments` con un escáner periódico.

## Consecuencias

- **Positivas:** facturación, lealtad y los demás reutilizan canales y consentimiento; cambiar de proveedor afecta un solo pack.
- **Obliga a:** M3.01 antes de M3.03.

## Cuándo revisarla

No se prevé.
