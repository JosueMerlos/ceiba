# Playbook: dar de alta una organización (onboarding asistido)

> En el MVP no hay auto-registro público: el alta la hace un **operador de plataforma** desde el back-office (M4.01), o desde la consola mientras M4.01 no exista. Ambos caminos usan **el mismo** servicio: `Tenancy::ProvisionOrganization`.
> Referencias: [03](../architecture/03-multi-tenancy.md), [04](../architecture/04-access-control.md), [05](../architecture/05-module-system.md), [13](../architecture/13-privacy-ley-787.md).

## 0. Antes del alta (comercial y legal)

- [ ] Acuerdo firmado: términos de servicio + **acuerdo de tratamiento de datos** (la empresa es responsable y la plataforma, encargada).
- [ ] Piloto: acuerdo de 3 meses gratis con el compromiso de uso diario y de compartir métricas.
- [ ] Recopilar: nombre legal, nombre comercial, empresas (giro, moneda NIO/USD), sucursales (dirección, teléfono, horarios), slug deseado, correo del dueño.

## 1. Provisión

Desde el back-office (formulario guiado) o la consola:

```ruby
Tenancy::ProvisionOrganization.call(
  organization: { name: "Grupo Salud & Estilo", legal_name: "…" },
  company:      { name: "Clínica Dental Sonrisa", slug: "sonrisa", business_type: "dental", currency: "USD" },
  branch:       { name: "Managua Centro", time_zone: "America/Managua" },
  owner:        { email: "dueno@ejemplo.com", full_name: "…" }
)
```

Esto, en una transacción y mediante hooks:

| Paso | Pack | Resultado |
| --- | --- | --- |
| Crear organización, empresa y sucursal | `tenancy` | Estructura mínima |
| Crear el membership `org_owner` (y el usuario si no existe) | `access` / `identity` | Dueño con invitación pendiente |
| Activar los módulos por defecto del plan | `modules` | `appointments` activo con settings por defecto |
| Sembrar plantillas de notificación | `notifications` | Recordatorios listos (se envían solo con consentimiento) |
| Enviar la invitación al dueño | `identity` | Correo con enlace (7 días) |
| Auditar | `audit` | Registro del alta con el operador como actor |

- [ ] Verificar en el back-office que la organización aparece con su empresa y su sucursal.

## 2. Primer acceso del dueño

- [ ] El dueño acepta la invitación, define su contraseña (12+ caracteres) y **configura 2FA** (obligatorio para `org_owner`).
- [ ] Acepta el aviso de privacidad de la plataforma.

## 3. Configuración inicial (con acompañamiento)

- [ ] Empresas y sucursales adicionales (si es un grupo).
- [ ] Branding: logo, colores (con la validación de contraste).
- [ ] Horarios de atención por sucursal.
- [ ] Catálogo de servicios (o **importación CSV**, M2.03).
- [ ] Profesionales y recursos; asignación a sucursales; horarios.
- [ ] Clientes existentes por CSV, **sin** consentimiento salvo evidencia: no recibirán recordatorios hasta que lo otorguen.
- [ ] Invitar al staff con sus roles (`branch_manager`, `receptionist`, `professional`).

## 4. Verificación antes de abrir al público

- [ ] Crear una cita de prueba desde el panel y cancelarla.
- [ ] Reservar desde `/c/<slug>` en un móvil y recibir la confirmación.
- [ ] Recordatorio de prueba recibido por WhatsApp y por correo.
- [ ] Compartir el enlace en Instagram y en el WhatsApp Business del negocio.

## 5. Seguimiento del piloto

- [ ] Llamada semanal de feedback (registrada en `docs/pilots/<org>.md`).
- [ ] Métricas (M4.06): % de no-show, % de reservas públicas, citas por día.

## Baja de una organización (offboarding, P3)

Exportación completa de sus datos → periodo de retención acordado → borrado por `organization_id` → certificado de borrado. Se diseña en detalle antes del primer caso real.
