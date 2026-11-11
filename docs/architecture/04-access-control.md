# 04 — Control de acceso

> **Implementado en M0.08** (`packs/platform/access`); la sección "Implementación (M0.08)" al final resume lo real y los desvíos. Decisiones: [ADR-0007](../adr/0007-pundit-sobre-cancancan.md), [ADR-0008](../adr/0008-permisos-como-datos.md), [ADR-0016](../adr/0016-credenciales-por-superficie.md). Hitos: M0.07, M0.08, M4.01, M4.02.

## Tres capas que no se sustituyen entre sí

| Capa | Pregunta | Dónde |
| --- | --- | --- |
| Autenticación | ¿Quién eres? | `platform/identity` (sesiones), `platform/access` (API keys) |
| Tenancy | ¿De qué organización es esta request? | `platform/tenancy` ([03](03-multi-tenancy.md)) |
| Autorización | ¿Puedes hacer **esta** acción sobre **este** recurso, en **este** alcance? | Pundit + `platform/access` |

## Principal

> **Contrato con la auditoría y la idempotencia (M0.11, implementado):** todo principal expone `actor_type` e `id`. `Access::Principal` los define (`actor_type` = `kind.to_s`: `user`, `system`, `api_key`, `public_token`; `id` = nil si no tiene identidad propia) e `Identity::Principal::User` declara `user`. `Audit` e `Idempotency` los usan tal cual y **lanzan `ArgumentError` si un principal no declara `actor_type`** (no se deriva del nombre de la clase). `PlatformStaff` (M4.01) deberá declarar `platform_staff`.

La autorización nunca pregunta "¿puede el **usuario**…?" sino "¿puede el **principal**…?":

```
Access::Principal
  ├── User(user, memberships)            panel (cookie de sesión)
  ├── ApiKey(api_key, scopes)            integraciones (Bearer)
  ├── PublicToken(token, appointment)    cliente final con enlace firmado (alcance mínimo)
  ├── System                             jobs internos
  └── PlatformStaff(staff, grant)        operador de plataforma (back-office, auditado)
```

Todos responden a la misma interfaz: `can?(permission_key, scope) → bool`.

## Permisos como datos

```
permissions          (key PK, module_key, description)          ← declarados por los manifiestos
roles                (id, key, scope_level, system BOOL)                  ← sin organization_id hasta los roles personalizados (P3)
role_permissions     (role_id, permission_key)
memberships          (id, organization_id, user_id, role_id, company_id NULL, branch_id NULL)
```

- **Las claves de permiso** siguen `<modulo>.<recurso>.<accion>`: `appointments.appointment.create`, `platform.branding.update`, `platform.reports.consolidated`.
- Los **manifiestos** de cada pack declaran sus permisos y el registro los sincroniza en la tabla `permissions` en cada despliegue. Un permiso usado en una policy y no declarado hace **fallar los tests**.
- `roles.system = true` son las plantillas de plataforma (sembradas, `organization_id NULL`). Los roles personalizados por organización (P3) serán filas con `organization_id`: **el diseño ya lo admite sin cambiar código**.
- `memberships` lleva columnas explícitas con FKs reales y `organization_id` (tenant + RLS). El CHECK de coherencia:

```sql
CHECK (
  (scope_level = 'organization' AND company_id IS NULL AND branch_id IS NULL) OR
  (scope_level = 'company'      AND company_id IS NOT NULL AND branch_id IS NULL) OR
  (scope_level = 'branch'       AND company_id IS NOT NULL AND branch_id IS NOT NULL)
)
```

(`scope_level` se denormaliza desde el rol para poder expresar el CHECK.)

**Reemplaza** al `UserRole(user_id, role_id, scope_id)` de los planes originales: aquel no tenía tipo de alcance ni integridad referencial.

## Resolución de permisos efectivos

- El permiso efectivo es la **unión** de los permisos de todos los memberships del usuario **cuyo alcance contiene** el recurso:
  - un membership de organización cubre todas sus empresas y sucursales;
  - uno de empresa cubre todas sus sucursales;
  - uno de sucursal, solo esa sucursal.
- Se calcula una vez por request y se memoriza en el principal: una consulta con `JOIN` a `role_permissions`, sin N+1.
- Además, el **módulo** del permiso debe estar **activo** en la empresa del recurso ([05](05-module-system.md)). Un permiso de `appointments` en una empresa sin el módulo = denegado.
- `/api/v1/me` devuelve los permisos efectivos por alcance para que el frontend **refleje** (no decida) qué mostrar.

## Pundit

```ruby
class Appointments::AppointmentPolicy < Access::BasePolicy
  def create? = can?("appointments.appointment.create", record.branch)
  def update? = can?("appointments.appointment.update", record.branch) ||
                own_appointment? && can?("appointments.appointment.update_own", record.branch)

  class Scope < Access::BasePolicy::Scope
    def resolve = scope.where(branch_id: branch_ids_with("appointments.appointment.read"))
  end
end
```

- `Access::BasePolicy` niega todo por defecto; cada policy vive **en su pack**.
- Prohibido preguntar por nombres de rol (`role == "receptionist"`) o `current_user.admin?`. Un linter custom lo detecta.
- `verify_authorized` y la verificación de `policy_scope` corren como `after_action` en `Api::BaseController` (no en `ApplicationController`: solo la API autoriza): un endpoint sin autorización falla en los tests.

## Catálogo de roles (plantillas de sistema)

| Rol | Alcance | Para qué |
| --- | --- | --- |
| `org_owner` | organización | Dueño del contrato: cobro, alta de empresas, transferencia de propiedad |
| `org_admin` | organización | Administración global, sin cobro ni borrado de la organización |
| `company_manager` | empresa | Responsable del negocio: catálogo, profesionales, branding, reportes de su empresa |
| `branch_manager` | sucursal | Responsable de una ubicación: agenda, personal, clientes de esa sucursal |
| `receptionist` | sucursal | Opera la agenda: crear, mover, cancelar, check-in |
| `professional` | sucursal | Su agenda, bloqueos propios, completar o marcar no-show |

`client` **no** es un rol: es el principal `PublicToken`, que no entra al panel.

## Matriz de permisos (versión corregida)

| Recurso / acción | org_owner | org_admin | company_manager | branch_manager | receptionist | professional |
| --- | --- | --- | --- | --- | --- | --- |
| Organización: ver/editar | ✅ | ✅ | — | — | — | — |
| Organización: cobro, borrar, transferir | ✅ | — | — | — | — | — |
| Empresas: crear/editar | ✅ | ✅ | ver la suya | **ver la suya** (lectura) | **ver la suya** (lectura) | **ver la suya** (lectura) |
| Sucursales: crear/editar | ✅ | ✅ | ✅ (su empresa) | ver la suya | **ver la suya** (lectura) | **ver la suya** (lectura) |
| Módulos de la empresa: activar/desactivar | ✅ | ✅ | — | — | — | — |
| **Branding** | — | **✅** | ✅ | — | — | — |
| Servicios y precios (`appointments.service.read` / `.manage`) | — | — | CRUD | ver | ver | ver |
| Override de duración por sucursal (`appointments.service.override_duration`) | — | — | ✅ | ✅ | — | — |
| Override de **precio** por sucursal (`appointments.service.override_price`) | — | — | ✅ | **—** | — | — |
| Profesionales (`appointments.professional.read` / `.manage` / `.assign` / `.read_own`, [ADR-0034](../adr/0034-horarios-ausencias-y-permisos-de-profesionales-y-recursos.md)) | — | — | CRUD | ver, asignar a su sucursal | ver | ver su perfil |
| Recursos (`appointments.resource.read` / `.manage`) | — | — | CRUD | CRUD de su sucursal | ver | ver |
| Horarios (`appointments.schedule.read` / `.manage` / `.read_own`) | — | — | ✅ | ✅ | ver | ver el propio |
| Ausencias (`appointments.time_off.read` / `.manage` / `.manage_own`) | — | — | ✅ | ✅ (de los asignados a su sucursal) | ver | las propias |
| Clientes (`platform.customer.read` / `.create` / `.update` / `.archive`; rutas por sucursal, [ADR-0033](../adr/0033-autorizacion-y-pii-de-clientes-y-servicios.md)) | — | — | ver, crear, editar, archivar | ver, crear, editar, archivar | ver, crear, editar, archivar | — hasta que existan las citas (luego, los de sus citas) |
| Citas | conteos | conteos | CRUD | CRUD | CRUD | ver y editar las propias |
| Reportes | consolidado (conteos) | consolidado (conteos) | su empresa | su sucursal | — | — |
| Usuarios: invitar | cualquier rol (incl. `org_admin`) | roles de empresa y sucursal | staff de su empresa | staff de su sucursal | — | — |
| API keys | ✅ | ✅ | — | — | — | — |

**Cambio de M0.08 (decisión de producto, "lectura de su alcance"):** todo rol con membership puede **leer** (datos básicos: nombre, zona horaria, dirección, moneda, estado) la sucursal y la empresa a las que pertenece. Motivo: el personal opera la agenda de una sucursal y necesita esos datos. Es solo lectura —crear/editar sigue según la matriz— y un membership de sucursal **no** da lectura de las sucursales hermanas. Las celdas en negrita son el cambio respecto a la matriz original.

Correcciones respecto a `plans/`: `org_admin` **sí** edita branding (la decisión ya lo decía; la matriz no). Se añade la fila de módulos y la de API keys.

**Reglas de composición**

- Deny by default: lo que no está en la matriz, se niega.
- `org_owner` y `org_admin` ven reportes consolidados **solo como conteos**; el acceso a datos personales para soporte será just-in-time y auditado (F5–F6).
- Invitaciones sin doble aprobación: invita quien tenga un rol de gestión en el alcance de destino.

> La matriz se codifica como **datos** (seed de `role_permissions`) y como **tabla de casos** en la suite de autorización ([12](12-testing-strategy.md)). Si ambas divergen, los tests fallan.

## Operador de plataforma

- Tabla `platform_staff` **separada** de `users`: un empleado de la plataforma no es miembro de ningún tenant.
- Login separado (`/platform`), con 2FA obligatorio.
- Acceso a datos de un tenant solo mediante un **grant just-in-time**: `platform_access_grants(staff_id, organization_id, reason, expires_at)`. Cada acción queda en `audit_events` con `actor_type = platform_staff`.
- Usa el rol de BD con bypass de RLS solo dentro de ese grant.

## API keys

Ver [11-security §API keys](11-security.md#api-keys). Pertenecen a la organización, tienen scopes `read:<modulo>` / `write:<modulo>`, y su principal se evalúa con el mismo Pundit: un scope se traduce a un conjunto de permisos del módulo.

## Implementación (M0.08)

Pack `platform/access` (depende de `tenancy` e `identity`). Lo que existe y cómo se usa:

### Datos

| Tabla | Tipo | Notas |
| --- | --- | --- |
| `permissions` | **global** | PK `key`; CHECK `<modulo>.<recurso>.<accion>` y que la clave empiece por su `module_key` |
| `roles` | **global** | `key` única, `scope_level` (CHECK), `system`; UNIQUE `(id, scope_level)` para la FK compuesta de memberships |
| `role_permissions` | **global** | PK `(role_id, permission_key)`, FKs con `ON DELETE CASCADE` |
| `memberships` | **tenant** (`create_tenant_table`) | FKs: `users`, `(role_id, scope_level) -> roles`, `(organization_id, company_id) -> companies`, `(organization_id, company_id, branch_id) -> branches`; CHECK `chk_memberships_scope`; UNIQUE `NULLS NOT DISTINCT (organización, usuario, rol, empresa, sucursal)` |

- **Por qué esas tres son globales y no tenant:** son el catálogo de la plataforma (los permisos los declaran los packs, los roles de sistema son plantillas iguales para todos). El guardián de tablas tenant (`Database::TenantTables.inconsistencies`) exige que "tiene `organization_id`" y "tiene política `tenant_isolation`" sean lo mismo: por eso estas tablas **no tienen `organization_id`** y `memberships` sí es tenant. Lo comprueba `packs/platform/access/spec/db/access_schema_spec.rb`.
- **Desvío:** `roles` no lleva `organization_id NULL` todavía. Una columna `organization_id` habría obligado a registrar `roles` como tabla tenant (y la suite de aislamiento la trata como tal), y una tabla mixta —filas globales y filas de una organización— necesita una política RLS propia (`organization_id IS NULL OR = tenant`). Cuando lleguen los roles personalizados (P3) se decide entonces: la columna con esa política, o una tabla tenant aparte. Hoy `roles.system` es siempre `true`.
- **Sucursal coherente con su empresa:** la FK compuesta `(organization_id, company_id, branch_id) -> branches` necesita un UNIQUE en `branches (organization_id, company_id, id)`; lo añade una migración de tenancy (`uq_branches_organization_id_company_id_id`, `CONCURRENTLY`). La base impide un membership de sucursal con la empresa equivocada.
- `scope_level` se denormaliza desde el rol (`before_validation` del modelo) y la FK `(role_id, scope_level)` impide que lo contradiga.

### Permisos: registro y sincronización

- `Access.register_permissions(module_key, "clave" => { description:, roles: [...] })`: lo llaman los packs desde `config.to_prepare` (sobrevive a la recarga de desarrollo; volver a registrar un módulo **reemplaza** lo que declaró). Valida formato de clave, prefijo = módulo, roles de sistema conocidos y claves repetidas entre módulos (`ArgumentError`).
- Los **roles que reciben cada permiso van en la declaración**: la matriz es dato. La parte de plataforma está en `packs/platform/access/config/initializers/platform_permissions.rb` (organización, empresa, sucursal, módulos, branding, usuarios, API keys, reportes consolidados). Solo organización, empresa y sucursal (lectura) tienen endpoint en M0.08; el resto se declara ya para que la matriz sea completa.
- `Access.sync!` lleva el registro a la base (permisos, 6 roles de sistema, `role_permissions`), es **idempotente** y el registro es la fuente de verdad (lo no declarado se retira). Corre en cada despliegue: `bin/rails access:sync`, encadenado a `db:migrate`, `db:prepare` (que no invoca `db:migrate`) y al inicio de `db:seed`; como paso explícito de release es `bin/rails access:sync`. **Red de seguridad:** un registro vacío (un proceso que no cargó los packs) lanza `Access::SyncRefused`, y cualquier *retirada* de permisos o concesiones exige `ACCESS_SYNC_ALLOW_PRUNE=1` (o `allow_prune: true`); sin la autorización aborta sin cambiar nada y lista lo que retiraría. Solo añadir nunca la necesita. Un `pg_advisory_xact_lock` serializa despliegues simultáneos. La suite lo ejecuta una vez en `before(:suite)` (`spec/support/access_catalog.rb`).
- **Criterio 8 (permiso usado y no registrado):** (a) en ejecución, `can?`/`reach` con una clave sin registrar lanza `Access::UnknownPermission` (un bug, nunca una denegación silenciosa; sale como 500); (b) estáticamente, `lib/ci/policy_permissions.rb` escanea `packs/*/*/app/policies/**` y `spec/lib/ci/policy_permissions_spec.rb` falla si alguna policy usa un permiso que no está en `Access.permission_keys`.

### Principal y permisos efectivos

- `Access::Principal` es la interfaz (`can?(key, scope)` y `kind`): `User` (memberships), `System` (todo permiso registrado), y `ApiKey` / `PublicToken` **solo como interfaz que niega todo** hasta M4.02 / M3.04.
- `Access::Scope` (organización | empresa | sucursal, con sus ids) es lo que las policies pasan a `can?`; los modelos de otros packs son privados, así que se pasan ids.
- `Principal::User#activate!(organization_id)` hace **la única consulta de permisos de la request** (un `LEFT JOIN` de `memberships` con `role_permissions`, acotado por el tenant) y deja los datos en un `Access::Grants` inmutable. Después `can?`, `reach`, `member?`, `sees_company?` no tocan la base (`principal_user_spec`: 1 consulta al activar, 0 en 250 `can?`).
- **Lectura ascendente (`from_descendants: true`):** un permiso de lectura de un alcance superior puede declararse así para que un membership de **sucursal** lo ejerza también sobre la **empresa** de su sucursal (hoy `platform.company.read`, decisión de producto de M0.08). `Grants` lo guarda aparte (`@upward_company_keys`): no hace *visibles* las sucursales hermanas ni da ningún otro permiso de empresa.
- **Alcances de sucursal verificados:** `Grants#allows?` no confía en el `company_id` del `Scope`: con un membership de empresa, la sucursal debe ser de ESA empresa (precargadas en la misma consulta con un `JOIN` a `branches`; las creadas después se verifican con una consulta memorizada). Un `Scope.branch(company_id: A, branch_id: B1)` forjado no obtiene los permisos de A.
- Cobertura jerárquica: org ⊃ empresa ⊃ sucursal. Un permiso de **organización** solo lo cubre un membership de organización (uno de empresa no cubre "la organización").
- **Solo cuenta la organización activa** (criterio 4): un scope de otra organización, o un principal sin activar, niega.
- `Principal::User#reach(key)` (`Access::Reach`: toda la organización / empresas / sucursales) alimenta los `Scope` de las policies con una condición SQL en vez de preguntar fila por fila.
- `Principal::User#organization_ids` (selector de contexto, `GET /organizations`) cruza tenants a propósito: vive en `Access::MembershipDirectory`, único archivo con `ActsAsTenant.without_tenant` en este pack, en `AllowedFiles` del cop `Ceiba/TenantBypass`. **Con RLS (M4.03)** necesitará una política por usuario o el rol de plataforma (tarea de M4.03).

### Del request al recurso

`Api::BaseController` incluye `Access::Authorization`, así que **todo** controlador de la API:

1. envuelve la identidad de la sesión en `Access::Principal::User`;
2. si la ruta trae `organization_id` (o el parámetro equivalente), resuelve el contexto con `Access::RouteContextResolver` **antes** de la acción;
3. verifica `verify_authorized` tras toda acción y `verify_collection_scoped` tras toda acción que no autorizó un **registro** concreto —autorizar una clase o una relación (cualquier acción de colección, se llame `index`, `search`...) exige además `policy_scope`—, **dentro** del contexto: si fallan, el error revierte la transacción (nada escrito sobrevive) y responde 500 sin el cuerpo. No hay que declarar qué acciones son de colección.

Orden de decisiones del resolvedor (`organizations/:organization_id/companies/:company_id/branches/:branch_id`):

| Situación | Respuesta |
| --- | --- |
| Organización inexistente, id que no es un UUID, o sin membership del principal | `404 resource.not_found` (idéntico: no revela existencia) |
| Organización **suspendida** y el principal es miembro | `403 access.organization_suspended` |
| Empresa/sucursal inexistente, de otra organización/empresa, o fuera del alcance de sus memberships | `404 resource.not_found` |
| Visible, pero la policy niega la acción | `403 access.forbidden` |

- **Organizaciones suspendidas (decisión M0.08):** `Tenancy.with_context` las acepta (es tenancy, no autorización); el resolvedor las rechaza con 403 para sus miembros en **toda** ruta bajo la organización (incluido su `show`), pero `GET /organizations` las sigue listando con `status: "suspended"` para que la SPA lo explique. A quien no es miembro se le sigue respondiendo 404: la suspensión no revela que existe. Los jobs (que no pasan por rutas) no se ven afectados; si un job debe omitir organizaciones suspendidas lo decide él (M0.09/M0.13).
- Un controlador cuyo recurso **es** la organización/empresa/sucursal declara qué parámetro la identifica: `route_context organization: :id` (así `organizations#show` valida el membership igual que una ruta anidada).
- **El contexto sale SOLO de `request.path_parameters`** (lo que el router extrae de la ruta), nunca de `params`: una query `?organization_id=` o un cuerpo no pueden fijarlo (`route_params_spec.rb`). Una sucursal sin empresa en la ruta es 404.
- Una acción que de verdad no autoriza (login, sesión, logout) declara `skip_authorization!(reason:, only:)`: el motivo y `only:`/`except:` son obligatorios (no existe el skip de todo un controlador), la lista queda en `authorization_skips` y `spec/requests/api/authorization_spec.rb` **recorre las rutas reales** y la compara con una allowlist con motivo (hoy: las cuatro acciones de `SessionsController`). El cop `Ceiba/AuthorizationSkips` prohíbe cualquier otro modo de saltarse la verificación (`skip_after_action :verify_*`, `skip_authorization`, `skip_policy_scope`, redefinir las verificaciones).
- **La acción entera corre dentro de la transacción de `Tenancy.with_context`.** Consecuencias: (1) una transacción abierta durante toda la request (aceptable en lecturas cortas; vigilar endpoints largos, llamadas externas y jobs encolados dentro de la acción); (2) la guarda `transaction_open?` de `Events.publish` ([06](06-events-and-jobs.md)) **pierde valor** en estas rutas: siempre pasa, así que ya no avisa de un olvido; la disciplina de publicar junto al cambio de datos es del caso de uso. **Los GET/HEAD corren en una transacción de SOLO LECTURA** (`with_context(read_only: true)` → `SET TRANSACTION READ ONLY`, solo el contexto más externo la fija): una escritura accidental en una lectura falla en la base (`read_only_requests_spec.rb`).

### Policies de organización, empresa y sucursal

Viven en **`access`** (`Access::OrganizationPolicy`, `CompanyPolicy`, `BranchPolicy`) y no en `tenancy`: `access` depende de `tenancy` (resuelve el contexto y registra el hook) y `packwerk validate` rechaza los ciclos. Los controladores las pasan con `policy_class:` / `policy_scope_class:`. Sus controladores también viven en `access` (`Api::V1::Access::*`); `tenancy` expone para ello `Tenancy::Directory` (solo lectura: `organizations_for(ids)`, sin `Organization.all`; registros y relaciones `readonly`: guardar o borrar UN registro lanza `ReadOnlyRecord`, pero **las relaciones no impiden escrituras masivas** (`update_all`/`delete_all`/`readonly(false)`) y `Tenancy::Context` exige modelos reales, así que no son value objects; el cop `Ceiba/DirectoryWrites` detecta esas escrituras fuera de tenancy, sobre cadenas que parten de `Tenancy::Directory`) y los serializers públicos. **Las policies de los módulos de negocio sí viven en su pack** y heredan de `Access::BasePolicy` (deny by default: todas las acciones `false`, `Scope#resolve` = `none`).

| Endpoint | Autorización |
| --- | --- |
| `GET /api/v1/organizations` | `index?` para cualquier usuario; el Scope lista las organizaciones con membership. **Excepción documentada del selector de contexto:** devuelve un *resumen* (`id`, `name`, `status`: `OrganizationSummary`), no la organización completa; el detalle (razón social, país, fechas) exige `platform.organization.read` |
| `GET /api/v1/organizations/:id` | `platform.organization.read` (owner, admin); el resto, `403` |
| `GET .../companies` · `GET .../companies/:id` | `platform.company.read` (todo rol con membership, para su propia empresa); el Scope lista solo las alcanzadas |
| `GET .../companies/:company_id/branches` · `.../branches/:id` | `platform.branch.read`; el Scope: empresas alcanzadas más sucursales alcanzadas |

Con la decisión "lectura de su alcance", `receptionist` y `professional` leen su sucursal y su empresa y `branch_manager` también su empresa; ninguno lee sucursales hermanas ni la organización (`GET /organizations/:id` es solo de `org_owner`/`org_admin`: 403 para el resto). `GET /api/v1/me` (M0.09, [05](05-module-system.md#implementación-m009)) devuelve lo que la SPA necesita.

### Pruebas y linter

- **Harness de la matriz** (`packs/platform/access/spec/authorization_matrix/matrix_spec.rb`, corre en `bin/ci backend-test`): la matriz de plataforma copiada a mano como tabla de casos; compara (1) los datos sembrados, (2) el motor `can?` para 6 roles × 16 permisos × {organización, empresa propia/ajena, sucursal propia/hermana/ajena} y (3) la API real (404/403/200) para 6 roles × empresa propia/ajena × sucursal propia/hermana/ajena, el `show` de la organización por rol, el **contenido filtrado de los listados** (empresas y sucursales de A y de B) y un usuario de **otra organización** (404 en todo). Si el seed o el motor divergen de la tabla, falla.
- **Cop `Ceiba/AccessPolicyRoles`** (`lib/rubocop/cop/ceiba/`, `backend-lint`): en `packs/*/*/app/policies` prohíbe `admin?`, `role`/`roles`/`has_role?`/`memberships`... (también vía `send`/`public_send`/`__send__`), `instance_variable_get`, y cualquier literal que sea una clave de rol de sistema, incluidas las formas partidas (`"org_" "owner"`, `"org_#{x}"`, `"a" + "b"`).
- **Cop `Ceiba/AuthorizationSkips`**: en los controladores, ver arriba; además detecta asignar `@_pundit_*`, `define_method`/`alias_method`/`undef_method` sobre las verificaciones. `AccessPolicyRoles` detecta también `method(:role)`, `instance_eval`/`instance_exec` y `%w[org_ owner].join`.
- **`from_descendants`** solo se acepta en permisos de lectura (acciones `read`, `list`, `show`, `view`); en uno de escritura `register_permissions` lanza `ArgumentError`.
- **Escáner de permisos** (`lib/ci/policy_permissions.rb`, con Prism): además de los literales no registrados, toda llamada a `can?`/`reach` cuyo primer argumento no sea un literal de cadena es una violación (no se puede verificar).
- Para un rol nuevo de sistema hay que tocar `Access::SYSTEM_ROLES`, el cop (lista `ROLE_KEYS`) y la matriz del spec: es a propósito.

### Alta de una organización con dueño

`Tenancy::ProvisionOrganization.call(organization:, company:, branch:, extras: { owner: })`. `extras` es un Hash que Tenancy **no interpreta**; llega congelado a los hooks en `result.extras` (sin `extras:` todo funciona como antes). El hook `Access::OwnerHook` (clave `:access_owner`, registrado en `config.to_prepare`) espera `owner` = `Identity::Principal::User` (lo que devuelve `Identity::ProvisionUser.call(email:, full_name:, password:)`), crea el membership `org_owner` **en la misma transacción** y un `owner` de otro tipo revierte todo. Sin `owner` la organización nace sin dueño (el alta con invitación llega con M4.01). `Access::GrantRole.call(user:, role_key:, organization:, company: nil, branch: nil)` es el camino público para el resto de concesiones (seeds; invitaciones en M4.01).

### Módulos y permisos (M0.09)

- **`Access.module_gate`**: el permiso de un módulo exige además que el módulo esté activo en la empresa del alcance ([05](05-module-system.md#implementación-m009)). access no depende de modules (ciclo): `platform/modules` instala un gate (`gated?`, `active_companies_by_module`) al arrancar. `Principal::User#can?`/`reach` lo consultan; la consulta es perezosa, **una por principal** y no se hace al activar ni para permisos `platform.*` (el spec de "UNA consulta al activar" sigue en pie). Sin contexto de tenancy el gate niega.
- Nuevas piezas públicas: `Access.with_context(principal:, organization_id:, company_id:, branch_id:, read_only:)` (el resolvedor de rutas para endpoints sin contexto en la ruta, como `/me`), `Principal::User#module_active?` y `#permission_keys_in(company_id:, branch_id:)`.
- Los manifiestos registran sus permisos con `Access.register_permissions` (los roles salen de su `role_grants`) y `Access.sync!` los lleva a la base con todas sus salvaguardas; `bin/rails modules:sync` valida los manifiestos y delega en `access:sync`.
- Allowlist de skips: se añadió `Api::V1::Modules::MeController#show`.
