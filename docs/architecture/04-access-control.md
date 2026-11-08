# 04 — Control de acceso

> Decisiones: [ADR-0007](../adr/0007-pundit-sobre-cancancan.md), [ADR-0008](../adr/0008-permisos-como-datos.md), [ADR-0016](../adr/0016-credenciales-por-superficie.md). Hitos: M0.07, M0.08, M4.01, M4.02.

## Tres capas que no se sustituyen entre sí

| Capa | Pregunta | Dónde |
| --- | --- | --- |
| Autenticación | ¿Quién eres? | `platform/identity` (sesiones), `platform/access` (API keys) |
| Tenancy | ¿De qué organización es esta request? | `platform/tenancy` ([03](03-multi-tenancy.md)) |
| Autorización | ¿Puedes hacer **esta** acción sobre **este** recurso, en **este** alcance? | Pundit + `platform/access` |

## Principal

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
roles                (id, key, scope_level, organization_id NULL, system BOOL)
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
- `after_action :verify_authorized` y `verify_policy_scoped` en `ApplicationController`: un endpoint sin autorización falla en los tests.

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
| Empresas: crear/editar | ✅ | ✅ | ver la suya | — | — | — |
| Sucursales: crear/editar | ✅ | ✅ | ✅ (su empresa) | ver la suya | — | — |
| Módulos de la empresa: activar/desactivar | ✅ | ✅ | — | — | — | — |
| **Branding** | — | **✅** | ✅ | — | — | — |
| Servicios y precios | — | — | CRUD | ver | ver | ver |
| Override de duración por sucursal | — | — | ✅ | ✅ | — | — |
| Override de **precio** por sucursal | — | — | ✅ | **—** | — | — |
| Profesionales | — | — | CRUD | ver, asignar a su sucursal | ver | ver su perfil |
| Horarios y ausencias | — | — | ✅ | ✅ | ver | las propias |
| Clientes | — | — | ver, editar | ver, editar | ver, editar | los de sus citas |
| Citas | conteos | conteos | CRUD | CRUD | CRUD | ver y editar las propias |
| Reportes | consolidado (conteos) | consolidado (conteos) | su empresa | su sucursal | — | — |
| Usuarios: invitar | cualquier rol (incl. `org_admin`) | roles de empresa y sucursal | staff de su empresa | staff de su sucursal | — | — |
| API keys | ✅ | ✅ | — | — | — | — |

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
