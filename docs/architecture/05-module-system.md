# 05 — Sistema de módulos

> Decisiones: [ADR-0010](../adr/0010-modulos-por-empresa-y-manifiesto.md), [ADR-0011](../adr/0011-el-giro-no-es-un-modulo.md). Hitos: M0.09, M2.04 (settings de UI), F6 (entitlements).
> Esta es la pieza que hace **fácil extender** el ecosistema: un módulo nuevo se **declara**, no se cablea a mano.

## Tres conceptos que no deben mezclarse

| Concepto | Pregunta | Quién lo cambia | Tabla / herramienta |
| --- | --- | --- | --- |
| **Entitlement** | ¿El plan contratado **permite** este módulo y con qué límites? | Plataforma (cobro) | `plans`, `plan_entitlements`, `subscriptions` (F6) |
| **Activación** | ¿La empresa **tiene encendido** el módulo? | `org_owner` / `org_admin` | `company_modules` |
| **Feature flag** | ¿Esta **funcionalidad nueva** ya está liberada para esta organización? | Desarrollo | Flipper (por organización) |

Regla: **activar exige entitlement**; un flag nunca sustituye una activación ni un entitlement. Hasta F6, todos los planes tienen entitlement a `appointments` (sin límites).

## Manifiesto

Cada pack de `modules/` tiene `manifest.rb`. El registro (`platform/modules`) lo carga al arrancar y lo valida:

```ruby
Modules.define :appointments do
  name        "Citas"
  version     "1.0"
  requires    []                         # otros módulos necesarios para activarlo
  platform    %i[customers notifications] # capacidades de plataforma que usa

  permissions do
    permission "appointments.appointment.read"
    permission "appointments.appointment.create"
    permission "appointments.appointment.update"
    permission "appointments.appointment.update_own"
    permission "appointments.service.manage"
    # …
  end

  role_grants do                          # plantilla por defecto: qué roles de sistema reciben qué permisos
    grant :company_manager, all: true
    grant :receptionist, %w[appointments.appointment.read appointments.appointment.create …]
  end

  api_scopes "read:appointments"  => %w[appointments.appointment.read appointments.service.read],
             "write:appointments" => %w[appointments.appointment.create appointments.appointment.update]

  settings_schema "config/settings.schema.json"  # JSON Schema de company_modules.settings
  settings_levels %i[company branch]             # en qué niveles se puede sobrescribir

  publishes   %w[appointments.appointment_booked.v1 appointments.appointment_completed.v1 …]
  subscribes  {}                                 # evento => suscriptor

  navigation  [{ key: "agenda", path: "/agenda", permission: "appointments.appointment.read" }, …]

  on_enable   Appointments::Lifecycle::OnEnable    # siembra datos por defecto para la empresa
  on_disable  Appointments::Lifecycle::OnDisable   # detiene envíos programados; los datos se conservan
end
```

**Validaciones del registro (fallan el arranque y CI):**

- `key` único y estable (snake_case); nunca se renombra.
- Toda clave de permiso empieza por `<key>.`.
- `requires` sin ciclos y referenciando módulos existentes.
- Todos los eventos de `publishes` tienen un esquema registrado ([06](06-events-and-jobs.md)).
- El JSON Schema de settings es válido y trae `default` en cada propiedad.

## Activación por empresa

```
company_modules
  id, organization_id, company_id, module_key, enabled_at, disabled_at NULL, settings JSONB, timestamps
  UNIQUE (company_id, module_key)
  FK (organization_id, company_id) → companies
```

- `module_key` es un identificador estable, **nunca** un booleano por módulo en `companies`.
- Activar = `Modules::Enable.call(company:, key:)`: verifica entitlement y `requires`, crea o reactiva la fila, ejecuta `on_enable` y emite `platform.module_enabled.v1`. Todo idempotente.
- Desactivar **no borra datos**. El módulo desaparece de la navegación y la API (`404`), y sus jobs programados se detienen. Reactivar recupera todo.
- Ningún módulo se activa a nivel organización: el negocio real vive en la empresa.

## Settings con jerarquía

- Esquema por módulo (JSON Schema) con valores `default`.
- Resolución: **default del esquema → empresa (`company_modules.settings`) → sucursal (`branch_module_settings`, solo para claves permitidas en `settings_levels`)**.
- `Modules.settings_for(:appointments, branch:)` devuelve el objeto resuelto y validado.
- Ejemplos para `appointments`: `min_lead_time_minutes` (120), `max_advance_days` (60), `cancellation_window_hours`, `public_booking_enabled`.
- Escribir settings valida contra el esquema; un valor inválido es un `422` con detalle por campo.

## Cumplimiento (enforcement) en tres lugares

| Lugar | Mecanismo |
| --- | --- |
| Rutas/API | Concern `RequiresModule(:appointments)` en los controladores del pack → `404` si no está activo en la empresa del contexto |
| Autorización | `Principal#can?` exige que el módulo del permiso esté activo en la empresa del recurso |
| Jobs/suscriptores | El bus de eventos no entrega un evento a un suscriptor de un módulo inactivo para esa empresa; los escáneres filtran por empresas con el módulo activo |

**Ocultar en el frontend no es control de acceso**: la UI solo refleja lo que dicen `/me` y el backend.

## Frontend: registro de módulos

`/api/v1/me` devuelve, para el contexto elegido:

```json
{
  "principal": { "id": "…", "name": "…" },
  "context": { "organization": {…}, "company": {…}, "branch": {…} },
  "modules": [{ "key": "appointments", "version": "1.0", "settings": {…} }],
  "permissions": ["appointments.appointment.read", "…"],
  "navigation": [{ "module": "appointments", "key": "agenda", "path": "/agenda" }]
}
```

El panel tiene un registro estático `frontend/apps/panel/src/modules/<key>/index.ts` (rutas lazy, items de navegación, componentes). Solo **monta** los módulos que `/me` reporta activos y filtra la navegación por permiso ([08](08-frontend.md)).

## Ciclo de vida de un módulo

| Momento | Qué pasa |
| --- | --- |
| Despliegue | El registro sincroniza `permissions` y `role_permissions` de plantillas de sistema; los esquemas de eventos se validan |
| Provisión de una organización | El hook de `modules` activa los módulos por defecto del plan |
| Activación | `on_enable` (p. ej. siembra horarios por defecto de las sucursales) |
| Desactivación | `on_disable`; datos intactos |
| Evolución | Cambios de settings compatibles con el esquema (agregar claves con default); los cambios incompatibles requieren migración de datos y subir la versión |

## Qué no es un módulo

- **El giro** (dental, salón): es configuración de la empresa ([ADR-0011](../adr/0011-el-giro-no-es-un-modulo.md)). Un salón y una clínica usan el mismo pack `appointments`.
- **Capacidades de plataforma** (clientes, notificaciones, auditoría): no se activan ni desactivan; siempre existen.
