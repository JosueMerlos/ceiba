# 05 — Sistema de módulos

> **Implementado en M0.09** (`packs/platform/modules`); la sección "Implementación (M0.09)" al final resume lo real y los desvíos. Decisiones: [ADR-0010](../adr/0010-modulos-por-empresa-y-manifiesto.md), [ADR-0011](../adr/0011-el-giro-no-es-un-modulo.md). Hitos: M0.09, M2.04 (settings de UI), F6 (entitlements).
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

## Implementación (M0.09)

Pack `platform/modules` (namespace `Modules`; depende de `tenancy`, `access`, `events` y `audit`). API pública: `Modules.define`, `Modules.registry`, `Modules.load!`, `Modules.enabled?(company, key)`, `Modules.settings_for(key, company:, branch:)`, `Modules.entitled?`, `Modules.default_keys`, `Modules.flag_enabled?`, `Modules::Enable`, `Modules::Disable`, `Modules::UpdateSettings`, `Modules::RequiresModule`, `Modules::Registry`/`Manifest`/`FlagActor` y los errores. El resto (modelos, loader, gate, controladores) es privado.

### Manifiesto y registro

- `packs/modules/<key>/manifest.rb` llama a `Modules.define :<key>`. El registro **descubre por archivo** (`Dir.glob` + `Kernel.load`, `Modules::Loader`) y no referencia ninguna constante de módulo: `visible_to: []` queda intacto y no hizo falta tocar `PackContract::ALLOWED_VISIBLE_TO`. La key debe coincidir con el nombre del pack.
- Se carga y valida en `config.to_prepare` (arranque y cada recarga): **un manifiesto inválido falla el arranque** con la lista completa de problemas. `bin/rails modules:sync` (paso de release) valida y delega en `access:sync`.
- Campos: solo los de este documento. Un campo desconocido es un error. Matices del DSL real:
  - `permission "<key>.<recurso>.<accion>", description: "…"` — la descripción es **obligatoria** (la exige `Access.register_permissions`).
  - `role_grants`: `grant :rol, %w[…]` o `grant :rol, all: true`; los roles deben ser de sistema y los permisos, del módulo.
  - `settings_schema` acepta la ruta de un JSON Schema (relativa al pack) o un Hash. Se valida: JSON Schema válido, `type: object` con `properties`, **`default` en cada propiedad y que el default cumpla su esquema**, `additionalProperties: false` forzado. La extensión **`x-levels`** de una propiedad limita los niveles en que se puede sobrescribir (p. ej. `["company"]`); sin ella valen los de `settings_levels`.
  - **Cotas obligatorias** (sondas P2b/P3 de la revisión): todo `array` lleva `maxItems`, toda cadena libre `maxLength` (un `enum`/`const` basta) y todo número `minimum` y `maximum`, también dentro de objetos y elementos de arrays. Red de seguridad en la base: `CHECK pg_column_size(settings) < 16384` en `company_modules` y `branch_module_settings`.
  - Los nombres de las propiedades de settings **no pueden coincidir con `filter_parameters`** (`_key`, `token`, `secret`, `digest`…): la auditoría de settings enmascara por nombre y perdería el valor. Los secretos no van en settings.
  - `publishes` exige esquema registrado (`Events::Schemas`); `navigation` exige `key`, `path` y un permiso del módulo; `api_scopes` se llama `read:<key>`/`write:<key>` y apunta a permisos del módulo; `on_enable`/`on_disable` son cadenas con nombre de constante (se resuelven con `constantize`/`safe_constantize` al ejecutarse y reciben `call(company:)`; `on_enable` recibe además `first_activation:` (verdadero solo si esa llamada creó la fila: el módulo siembra una vez y respeta lo que la empresa haga tras reactivarlo)).
  - `subscribes` se acepta y valida (nombres de evento) pero **el registro no cablea suscriptores todavía**: no existe ninguno hasta F1. Lo pendiente —**para F1**, con el primer módulo que tenga suscriptores—: que el bus (`Events::DeliverJob`) no entregue a un suscriptor de un módulo inactivo (nota de cierre de M0.10).
- `requires`: existentes y sin ciclos (`Registry#validate!`, el ciclo se muestra: `a -> b -> a`). Al desactivar, un módulo que otro **activo** requiere no se deja desactivar (`Modules::RequiredByOthers`, 409).

### Datos

`company_modules` (tenant): una fila por `(empresa, módulo)` con `UNIQUE (organization_id, company_id, module_key)` (equivale al `(company_id, module_key)` del diseño y es el destino de una FK compuesta), índice parcial de activos, CHECKs de formato y de `settings` objeto. `branch_module_settings` (tenant): overrides por sucursal, con FK compuesta a la sucursal **y** a `company_modules` (el módulo debe haberse activado alguna vez en la empresa), `UNIQUE (organization_id, branch_id, module_key)`. Desactivar solo pone `disabled_at`: la fila, los settings y los de las sucursales se conservan; reactivar reutiliza la fila.

### Activación y eventos

`Modules::Enable.call(company:, key:)` / `Modules::Disable.call(company:, key:)`: una transacción que **serializa por empresa** (`pg_advisory_xact_lock` sobre la empresa: sin él, Enable de un complemento y Disable de su base podían dejar un módulo activo sin lo que requiere; spec de carrera con COMMIT real) con fila (bloqueada), hook, `Events.publish("platform.module_enabled.v1" | "platform.module_disabled.v1", company_id:, module:)` (payload **confirmado**; la organización viaja en el sobre) y `Audit.record(action: "module.enabled" | "module.disabled", subject: company_module, before: { active: … }, after: { active: … })`. **Idempotentes**: una repetición devuelve `changed: false` y no ejecuta hook, evento ni auditoría. Una carrera por la primera fila la resuelve el UNIQUE. `Modules.entitled?` devuelve `true` (TODO F6: planes y `plan_entitlements`). Los módulos por defecto de una organización (`Modules.default_keys`, hoy `appointments`; en F6, los del plan) los activa el hook `after_provision` `Modules::ProvisioningHook` (key `:modules_defaults`), dentro de la transacción de la provisión: si falla, se revierte todo. `Tenancy::AddCompany` **no** activa módulos por defecto (fuera de alcance; lo decide M4.01).

### Settings

`Modules.settings_for(:appointments, company:, branch:)` = defaults del esquema → `company_modules.settings` → `branch_module_settings.settings` (solo claves cuyo nivel incluye `branch`), validado contra el esquema y devuelto como copia. `Modules.settings_for` lanza `InvalidSettings` si lo guardado ya no cumple el esquema, pero **`/me` degrada** ese módulo a los defaults del esquema (sigue activo) y lo reporta con `Rails.error.report`: un dato malo de un módulo no deja a la SPA sin contexto. `Modules::UpdateSettings.call(company:, key:, settings:, branch: nil)` combina las claves enviadas con los overrides del nivel (`nil` quita el override), valida el resultado y lanza `Modules::InvalidSettings` con `errors[]` por campo (`reminders.0.offset_minutes`; códigos `minimum`, `type`, `required`, `unknown`, `not_allowed_at_level`…, mensajes en `es-NI`) **sin guardar nada**. Audita `module.settings_updated` con solo las claves tocadas.

### Cumplimiento

- **Rutas**: `include Modules::RequiresModule` + `requires_module :<key>` en el controlador. Corre tras resolver el contexto y **antes** de la autorización; módulo inactivo (o ruta sin empresa) = el mismo `404 resource.not_found` que un recurso inexistente. Incluirlo sin declarar el módulo falla cerrado (error de programación). **Exige empresa en el contexto**: no sirve para endpoints a nivel organización (p. ej. conteos consolidados); esos endpoints, que llegan en F1, necesitan su propio mecanismo (pregunta abierta). El gate instrumenta su denegación (`denied.requires_module`) y el cop `Ceiba/ModuleGateSkips` prohíbe saltárselo (`skip_before_action :ensure_required_module_enabled!`, redefinirlo, `required_module = nil`).
- **Autorización**: `Access.module_gate` (punto de extensión de access, que no puede depender de modules) lo instala `Modules.load!`. `Principal::User#can?` exige además que el módulo del permiso esté activo en la empresa del alcance (en el de organización, en alguna); `reach` deja solo las empresas/sucursales con el módulo activo. La consulta (`company_modules` activos de la organización) es **una por principal**, perezosa y memoizada, y la reutiliza `RequiresModule`: una request no consulta dos veces. Es una foto por request (se descarta al reactivar el principal en otra organización). Los permisos `platform.*` no dependen de ningún módulo. **`Principal::System#can?` ignora el gate** a propósito: los jobs internos no son un usuario de una empresa; los escáneres deben filtrar ellos por empresas con el módulo activo.
- **Suite de cobertura de módulos** (`spec/requests/api/module_coverage_spec.rb`): todo controlador de `packs/modules/*` declara su módulo **y el gate está en los callbacks efectivos de cada acción** (sin `skip`, `only` ni `except`); toda ruta de un módulo inactivo responde 404 **y ese 404 lo emite el gate** (se comprueba la instrumentación, porque en una ruta de miembro un id desconocido da 404 por sí solo) y deja de hacerlo al activarlo. Las URLs se construyen con **ids reales** (`:branch_id` = una sucursal de la empresa; `:id` y demás, con `ModuleCoverageFactories.register("<key>", :id) { … }` en `spec/support`): el módulo con una ruta de miembro DEBE registrar su fabricante o la suite falla diciendo cuál (el primer módulo real con `show` lo hará). `/me` ante un override de sucursal inválido cae al nivel de empresa (no a los defaults de todo el módulo). El módulo `sample` (solo specs, `spec/support/sample_module*.rb`) ejercita la maquinaria; sus permisos se sincronizan dentro de la transacción de cada spec (contexto `"con el módulo sample sincronizado"`), nunca en la base compartida.

### API

| Endpoint | Detalle |
| --- | --- |
| `GET /api/v1/me` | Ver abajo |
| `PUT /api/v1/organizations/:o/companies/:c/modules/:key` | `{ "enabled": true|false }` (solo literales: otra cosa es 400); `platform.company_module.manage`. **Pregunta de producto abierta:** quién debe escribir los settings de una *sucursal*; hoy solo `org_owner`/`org_admin` (un `branch_manager` no puede) |
| `PATCH …/companies/:c/modules/:key/settings` | `{ "settings": {…} }`, nivel empresa; 422 con `errors[]` por campo |
| `PATCH …/companies/:c/branches/:b/modules/:key/settings` | Nivel sucursal. **Desvío**: la sucursal va en la ruta (cuarto nivel) y no como filtro, porque la API rechaza query string en las mutaciones (`request.query_not_allowed`) y así `Access::Authorization` valida la sucursal como cualquier ruta |

Errores de dominio (registrados en `Api::ErrorRegistry`): `modules.unknown_module` 404, `modules.not_entitled` 403, `modules.requirements_not_met` 409, `modules.required_by_others` 409, `modules.not_enabled` 409, `modules.invalid_settings` 422.

**`GET /api/v1/me[?organization_id=&company_id=&branch_id=]`**: `{ data: { principal: {id, name, email}, context: {organization, company, branch}, modules: [{key, version, settings}], permissions: [...], navigation: [{module, key, path}] } }`. 
- *Contexto*: parámetros (explícitos: si no son visibles, 404/403 como una ruta; `company_id` exige `organization_id`) → si no, el **último usado** → si no, la primera organización del usuario (por id) y su primera empresa visible (por id). Sin sucursal elegida, `branch` es `null` y los settings son los de la empresa. Un usuario sin memberships recibe 200 con el contexto vacío. Se valida con `Access.with_context` (API pública nueva de access, el mismo resolvedor de las rutas) y corre en transacción de solo lectura.
- *Último usado*: **cookie firmada `ceiba_context`** (`usuario:org:empresa:sucursal`, ligada al usuario: otra persona en el mismo navegador no la hereda y no hace falta borrarla en el logout, que es de `identity`; HttpOnly, SameSite=Lax, 90 días; prefijo `__Host-` con `secure_cookies`), una por navegador. Decisión: un GET no escribe en la base y es una conveniencia por dispositivo, no un dato del usuario; no es una credencial: se revalida en cada uso y si ya no hay acceso se cae al contexto por defecto; una cookie manipulada se ignora.
- *Permisos*: los que el principal ejerce **dentro** del contexto (de la organización, de la empresa, de cualquiera de sus sucursales o, si se eligió, de esa sucursal) cuyo módulo está activo; es una lista plana, no por alcance (el frontend refleja, no decide).
- *Navegación*: entradas de los manifiestos de módulos **activos** cuyo permiso está en `permissions`.
- Autorización: `skip_authorization!` en `MeController#show` (entrada en la allowlist de `authorization_spec.rb`): devuelve lo del propio principal y el contexto ya se valida contra sus memberships.

### Feature flags (Flipper)

`config.flipper.preload = false` (sin flags no se precarga nada en cada request, ni en `/api/health`; activarlo con una lista de rutas cuando existan flags). `flipper` y `flipper-active_record` **1.4.2** (tablas globales `flipper_features`/`flipper_gates`), actor = organización (`Modules::FlagActor.new(id)`, `flipper_id` `"Organization;<id>"`), `Modules.flag_enabled?(:flag, organization:)`. Sin flags definidos. En test Flipper usa un adaptador de memoria (`flipper/test_help`) vaciado en cada ejemplo. Un flag nunca activa un módulo.

### Appointments (manifiesto mínimo)

Seis permisos de la matriz de [04](04-access-control.md) más **`appointments.appointment.count`** (conteos, decisión de M0.09): la matriz dice que `org_owner`/`org_admin` ven citas solo como conteos y el criterio 7 exige navegación para el dueño recién provisionado; el permiso (más la entrada de navegación `summary`, `/agenda/summary`) lo resuelve sin darles el detalle. Settings de [domain/appointments](../domain/appointments.md) con sus niveles (`x-levels`). `publishes []` hasta F1 (sus esquemas de evento no existen aún).
