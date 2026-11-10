# Playbook: agregar un módulo nuevo

> Objetivo: que un módulo nuevo (p. ej. `loyalty`) se integre **declarándolo**, sin modificar `platform/`. Si algún paso exige tocar la plataforma, se justifica en un ADR: es una señal de que falta una capacidad o un punto de extensión.
> Referencias: [02](../architecture/02-modular-monolith.md), [05](../architecture/05-module-system.md), [06](../architecture/06-events-and-jobs.md), [04](../architecture/04-access-control.md).

## 0. Antes de escribir código

- [ ] ¿Es realmente un **módulo** (funcionalidad activable por empresa) y no configuración de uno existente ni una capacidad de plataforma? ([ADR-0011](../adr/0011-el-giro-no-es-un-modulo.md))
- [ ] Definir el `key` estable (snake_case, en inglés, **nunca** se renombra).
- [ ] Listar: qué eventos de otros módulos necesita, qué eventos publicará, qué capacidades de plataforma usa (clientes, notificaciones…).
- [ ] Si necesita datos de otro módulo de negocio: **solo por eventos**. Si necesita una respuesta síncrona de otro módulo, el diseño está mal o falta una capacidad de plataforma.
- [ ] ADR del módulo: propósito, límites y datos sensibles (¿requiere un consentimiento nuevo según la Ley 787?).
- [ ] Hitos en `docs/milestones/F<n>-<modulo>/` con la plantilla.

## 1. Esqueleto

```bash
bin/rails g pack modules/loyalty
```

Genera `package.yml` (capa `modules`, privacidad activa, `visible_to: []`), un `manifest.rb` **válido** (`Modules.define` con `name` y `version`, y la guía comentada de los campos), `config/locales/es-NI.yml` y un spec base. El módulo ya arranca y aparece en el registro, aunque aún no tenga permisos.

- [ ] `packwerk check` en verde con el pack vacío. Declara en `package.yml` solo lo que uses de `platform/*`; **no** hay que tocar `visible_to` ni `PackContract::ALLOWED_VISIBLE_TO`: la plataforma descubre el manifiesto por archivo.

## 2. Manifiesto

`packs/modules/loyalty/manifest.rb` (la key debe coincidir con el nombre del pack y no cambia nunca). Solo existen los campos de [05](../architecture/05-module-system.md); uno desconocido es un error. El registro lo carga y valida **al arrancar**: lo que esté mal falla con un mensaje que nombra el problema.

- [ ] `name`, `version "1.0"`, `requires` (módulos que deben estar activos en la empresa), `platform` (capacidades de plataforma).
- [ ] **Permisos** `permission "loyalty.<recurso>.<accion>", description: "…"` (prefijo = key, descripción obligatoria) y `role_grants` por defecto para los roles de sistema (`grant :receptionist, %w[…]` o `all: true`). Se registran solos en access; no hay que tocar `platform/access`.
- [ ] **Scopes de API** `read:loyalty` / `write:loyalty` apuntando a permisos del módulo.
- [ ] **Settings**: `config/settings.schema.json` con `default` en **cada** propiedad (que cumpla su propio esquema) y **cotas**: `maxItems` en arrays, `maxLength` en cadenas libres (un `enum` basta), `minimum` y `maximum` en números (el registro lo exige; la base limita `settings` a 16 KB), `settings_levels %i[company branch]` y, para las claves que solo se pueden fijar en la empresa, `"x-levels": ["company"]`. Los nombres no pueden ser sensibles (`*_token`, `*_key`, `secret`…): la auditoría los enmascararía; los secretos no van en settings.
- [ ] **Eventos** publicados (con su JSON Schema en `app/public/loyalty/events/`; `publishes` exige que existan) y `subscribes` (se valida, pero el cableado de suscriptores por módulo llega con el primero que exista: ver el pendiente en 05).
- [ ] **Navegación** `{ key:, path:, permission: }` con un permiso del módulo; `/me` solo la entrega si el usuario tiene ese permiso y el módulo está activo.
- [ ] Hooks `on_enable "Loyalty::Lifecycle::OnEnable"` (sembrar datos por defecto; se ejecuta **una vez por activación**) y `on_disable` (detener envíos o jobs; **conservar** los datos). Son cadenas; cada uno es un objeto con `call(company:)`, corre dentro de la transacción de Enable/Disable y, si lanza, no queda activado/desactivado.
- [ ] Controladores del módulo: nunca `skip_before_action :ensure_required_module_enabled!` (lo frena el cop `Ceiba/ModuleGateSkips` y la suite de cobertura de módulos).
- [ ] Si el módulo tiene rutas de miembro (`:id`...), registra en `spec/support` un fabricante de recurso real con `ModuleCoverageFactories.register` para cada parámetro: la suite de cobertura de módulos usa ids reales y falla si falta.
- [ ] Spec del manifiesto (modelo: `packs/modules/appointments/spec/manifest_spec.rb`): permisos, concesiones según la matriz de 04, scopes, defaults y niveles de los settings, navegación.
- [ ] Si debe activarse al provisionar una organización, añade su key a `Modules.default_keys` (hoy una lista fija; en F6 saldrá del plan). Es la única edición en `platform/modules`, y es temporal.

## 3. Datos

- [ ] Migraciones en `packs/modules/loyalty/db/migrate` usando `create_tenant_table` y `tenant_reference` (FKs compuestas).
- [ ] Dinero en `*_minor` + `currency`; tiempos en `timestamptz`; PII cifrada si aplica.
- [ ] Invariantes críticas como restricciones de BD.
- [ ] Factories que derivan `organization_id` del padre. La **suite de aislamiento** las exige: si falta una, falla.

## 4. Dominio y API

- [ ] Casos de uso en servicios; transacción + `Events.publish` + `Audit.record` juntos.
- [ ] Controladores bajo `/api/v1/organizations/:organization_id/companies/:company_id/loyalty/...` que heredan de `Api::BaseController` y declaran `include Modules::RequiresModule` + `requires_module :loyalty` (módulo inactivo = el 404 genérico, antes de autorizar). La suite de cobertura de módulos falla si un controlador de tu pack no lo declara. Las rutas van en `config/routes/<pack>.rb` y se montan con `draw` desde `config/routes.rb`.
- [ ] Policies en el pack que preguntan por **permisos**, nunca por roles. `can?` ya exige que el módulo esté activo en la empresa del recurso y `reach` se limita a las empresas donde lo está; no lo repitas en la policy.
- [ ] Specs de rswag por endpoint → regenerar OpenAPI y `api-client`.
- [ ] Errores con `code` estable (`loyalty.<error>`) y traducción en `es-NI`.

## 5. Suscriptores

- [ ] Uno por evento escuchado, en `app/subscribers/`, idempotente (lo garantiza `processed_events`; el efecto también debe ser seguro ante repetición). **Pendiente de plataforma:** hoy el bus no filtra por módulo activo; el primer módulo con suscriptores debe añadir ese filtro (nota de cierre de M0.10 y de M0.09).
- [ ] Spec: el mismo evento dos veces produce un solo efecto; con el módulo inactivo para la empresa, no se entrega.

## 6. Frontend

- [ ] `frontend/apps/panel/src/modules/loyalty/index.ts` con rutas lazy, navegación y permisos.
- [ ] Registrar en `modules/registry.ts`.
- [ ] Hooks sobre `packages/api-client`; componentes presentacionales con tests.
- [ ] Textos en i18n.

## 7. Matriz de autorización

- [ ] Añadir los permisos del módulo a la matriz de [04](../architecture/04-access-control.md) y a la tabla de casos de la suite de autorización (el harness de `packs/platform/access/spec/authorization_matrix` compara el motor con la tabla; las concesiones salen de `role_grants`).

## 8. Verificación final

- [ ] Las 6 suites de plataforma en verde (aislamiento, RLS, autorización, cobertura de módulos, contrato, eventos).
- [ ] Con el módulo **inactivo**: no aparece en `/me` (ni sus permisos ni su navegación), sus rutas dan `404` (suite de cobertura de módulos) y sus permisos no aplican en `can?`. (Que no reciba eventos: ver el pendiente de la sección 5.)
- [ ] Al **activarlo** en una empresa de seeds (`PUT …/modules/loyalty` con `{ "enabled": true }` o `Modules::Enable.call`): `on_enable` deja datos por defecto coherentes, queda el evento `platform.module_enabled.v1` y la auditoría `module.enabled`; repetirlo no cambia nada. Desactivar y reactivar conserva los datos.
- [ ] `bin/rails modules:sync` termina bien (valida los manifiestos y sincroniza permisos y concesiones; retirar permisos exige `ACCESS_SYNC_ALLOW_PRUNE=1`).
- [ ] **Cero cambios en `packs/platform/`** (salvo, mientras no existan los planes, la key en `Modules.default_keys`), o un ADR que los justifique.
- [ ] Docs: ADR del módulo, `domain/<modulo>.md`, glosario actualizado.
