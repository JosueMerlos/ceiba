# 03 — Multi-tenancy

> Decisiones: [ADR-0003](../adr/0003-tenant-es-la-organizacion.md), [ADR-0004](../adr/0004-jerarquia-organizacion-empresa-sucursal.md), [ADR-0005](../adr/0005-rls-preparado-activado-en-piloto.md), [ADR-0021](../adr/0021-cliente-unico-por-empresa.md), [ADR-0028](../adr/0028-usuario-multi-organizacion.md). Hitos: M0.04, M0.05, M4.03.

## Modelo

**Una base de datos, un esquema y `organization_id` en cada tabla tenant.** El tenant es la **organización**.

```
Organización (tenant: frontera dura entre clientes; facturación)
  └── Empresa (giro, marca, catálogo, profesionales, clientes; activa módulos)
        └── Sucursal (zona horaria, horarios, recursos, agenda)
              └── Profesionales / recursos asignados
```

| Nivel | Qué define | Qué NO define |
| --- | --- | --- |
| Organización | Contrato, plan, administradores globales, reportes consolidados (solo conteos) | Servicios, precios, horarios, zona horaria |
| Empresa | Giro, branding, moneda, catálogo de servicios, profesionales, clientes, módulos activos | Zona horaria, horarios de atención, recursos físicos |
| Sucursal | Zona horaria IANA, horarios de atención, recursos, agenda | Servicios propios (solo override de duración/precio), clientes |
| Profesional / recurso | Horario semanal, ausencias, citas, sucursales donde atiende | Precio base (solo override) |

**Reglas duras**

- Empresa y sucursal **no** son tenants: son **alcances de autorización** ([04](04-access-control.md)).
- El cliente es único **por empresa**; nunca se comparte entre empresas del grupo.
- Un registro profesional no cruza empresas; la **persona** (usuario) puede tener registros en varias empresas del grupo ([ADR-0020](../adr/0020-persona-separada-de-profesional.md)).
- Un usuario puede pertenecer a **varias organizaciones**; elige el contexto al entrar ([ADR-0028](../adr/0028-usuario-multi-organizacion.md)).

## Tres barreras (defensa en profundidad)

| # | Barrera | Qué detiene | Desde |
| --- | --- | --- | --- |
| 1 | `acts_as_tenant` con `require_tenant = true` | Consultas sin tenant o con un tenant equivocado en el código de aplicación | M0.05 |
| 2 | **FKs compuestas** `(organization_id, parent_id)` | Que un registro apunte a un padre de otra organización, aunque el código se salte validaciones | M0.04 |
| 3 | **Row Level Security** en PostgreSQL | Cualquier consulta (SQL crudo, `unscoped`, bugs de gemas) que lea filas de otra organización | Creada en M0.04, **activada en M4.03** |

### Barrera 2: FKs compuestas

Toda tabla padre tenant declara `UNIQUE (organization_id, id)`. Toda hija referencia **el par**:

```sql
ALTER TABLE branches
  ADD CONSTRAINT fk_branches_company
  FOREIGN KEY (organization_id, company_id)
  REFERENCES companies (organization_id, id);
```

Así la BD garantiza que `branch.organization_id = company.organization_id`. Es imposible, incluso con `update_columns`, crear una sucursal de la organización A colgada de una empresa de B.

### Barrera 3: RLS

Cada tabla tenant nace (helper `create_tenant_table`, M0.04) con:

```sql
ALTER TABLE <tabla> ENABLE ROW LEVEL SECURITY;   -- solo en M4.03
CREATE POLICY tenant_isolation ON <tabla>
  USING (organization_id = current_setting('app.organization_id', true)::uuid)
  WITH CHECK (organization_id = current_setting('app.organization_id', true)::uuid);
```

- La condición real (`create_tenant_table`) envuelve el setting en `NULLIF(..., '')` antes del cast a `uuid`: tras un `SET LOCAL` previo el setting queda como cadena vacía y `''::uuid` fallaría; así una conexión sin contexto ve cero filas en lugar de un error. Ver [09](09-data-conventions.md#tablas-tenant).
- Hasta M4.03 la política **existe pero RLS está deshabilitado** en la tabla. Activarlo es una migración, no un rediseño.
- La aplicación se conecta con un rol **sin** `BYPASSRLS` y que **no es dueño** de las tablas (el dueño ignora RLS salvo `FORCE ROW LEVEL SECURITY`). Las migraciones usan un rol dueño distinto (`app_owner`; la app usa `app_user`: ver [09](09-data-conventions.md#roles-de-base-de-datos)).
- `Tenancy.with_context` ejecuta `SET LOCAL app.organization_id = '<uuid>'` dentro de una transacción. `SET LOCAL` muere con la transacción, así que no hay fugas entre requests que comparten conexión del pool.
- Los caminos privilegiados (back-office, reportes consolidados de plataforma) usan un rol de BD separado con `BYPASSRLS`, en código explícito y auditado.

## Contexto por request y por job

```ruby
Tenancy::Context = Data.define(:organization, :company, :branch, :principal)
Current.context  # un único objeto inmutable por request/job
```

- **Request:** la organización y la empresa salen de la **ruta** (`/api/v1/organizations/:organization_id/companies/:company_id/...`), nunca del body. Se validan contra los memberships del principal antes de fijar el contexto.
- **Job:** recibe `organization_id` (y los ids que necesite) como argumentos; el middleware de Sidekiq reconstruye el contexto con `Tenancy.with_context`. **Nunca se lee `Current` dentro de un job.**
- `Tenancy.with_context` es el **único** punto que llama a `ActsAsTenant.with_tenant` y a `SET LOCAL`.

## Caminos privilegiados

| Caso | Cómo | Restricción |
| --- | --- | --- |
| Reportes consolidados de la organización | Dentro del tenant: no cruzan organizaciones, solo empresas | Solo conteos agregados, nunca datos personales |
| Back-office de plataforma | `Principal::PlatformStaff` + rol de BD con bypass | Cada acceso a datos de un tenant se audita; impersonación just-in-time con motivo y caducidad |
| Seeds, consola, migraciones de datos | `Tenancy.with_context` explícito por organización | Prohibido `ActsAsTenant.without_tenant` fuera de una allowlist revisada en CI |

## Provisión de tenants

`Tenancy::ProvisionOrganization` es el **único** camino para crear una organización con su primera empresa y su primera sucursal. Expone hooks `after_provision` que otros packs registran:

- `access`: crea el membership `org_owner` del usuario dueño.
- `modules`: activa los módulos por defecto según el plan (hoy, `appointments`).
- `notifications`: siembra las plantillas por defecto.

Ver [playbook de alta de organización](../playbooks/onboard-an-organization.md).

## Pruebas obligatorias

- **Suite de aislamiento genérica** (M0.05): descubre todos los modelos con `organization_id` y verifica, para cada uno, que sin tenant la consulta falla y que A no ve a B.
- **Pruebas de bypass de RLS** (M4.03): con `acts_as_tenant` desactivado a propósito, una consulta SQL cruda no devuelve filas de otra organización.
- La autorización **entre empresas de la misma organización** se prueba en la matriz de autorización ([12](12-testing-strategy.md)), no aquí.

## Migración de un cliente grande a su propia base (salida prevista)

Gracias a los UUIDv7 (sin colisiones) y a que toda fila lleva `organization_id`, extraer una organización es una exportación filtrada por `organization_id` hacia otra instancia, más el enrutamiento de conexión por tenant (`connects_to` de Rails). No está planificado; solo se deja **posible**.
