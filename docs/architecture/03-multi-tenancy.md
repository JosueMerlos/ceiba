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
- `Tenancy.with_context` fija `app.organization_id` con `set_config('app.organization_id', $2, true)` (el equivalente parametrizable de `SET LOCAL`: el id viaja como parámetro enlazado, **nunca interpolado**) dentro de una transacción. El setting muere con la transacción, así que no hay fugas entre requests que comparten conexión del pool; además, si el bloque termina bien, el setting se restaura al valor anterior (el del contexto externo si estaba anidado) para que tampoco se filtre al resto de una transacción ajena que lo envuelva. Ver [Contexto](#contexto-por-request-y-por-job).
- Los caminos privilegiados (back-office, reportes consolidados de plataforma) usan un rol de BD separado con `BYPASSRLS`, en código explícito y auditado.

## Tablas del pack (M0.05)

| Tabla | Tipo | Notas |
| --- | --- | --- |
| `organizations` | raíz del tenant (sin `organization_id`) | `name`, `legal_name`, `country_code` (`NI`, CHECK `^[A-Z]{2}$`), `status` (`active`/`suspended`) |
| `companies` | tenant (`create_tenant_table`) | `slug` **único global** (`uq_companies_slug`, CHECK `^[a-z0-9-]{3,40}$`, además lista de reservados en el modelo), `currency` (`NIO`/`USD`, CHECK), `locale`, `status` (`active`/`inactive`) |
| `branches` | tenant + `t.tenant_reference :company` | FK compuesta `fk_branches_company`; `time_zone` IANA (default `America/Managua`, validado contra TZInfo), `phone_e164` (CHECK E.164), `status` |

**`on_delete: :restrict` en todas las FKs** (el default de los helpers). Justificación: borrar una organización, una empresa o una sucursal con datos es un *offboarding* explícito (exportar, retener, borrar por `organization_id`: P3), nunca un efecto lateral de un `DELETE`; con `cascade`, un `destroy` accidental de la organización borraría en silencio todo su negocio, y con `nullify` ni siquiera es posible (`organization_id` es `NOT NULL`). Probado en `company_spec.rb`. El modelo `Organization` no declara `dependent:` a propósito: la base es quien protege.

Los modelos (`Tenancy::Organization`, `Company`, `Branch`) son **privados** del pack. API pública: `Tenancy.with_context`, `Tenancy::Context`, `Tenancy::ProvisionOrganization`, `Tenancy::AddCompany`, `Tenancy::AddBranch`, `Tenancy::TenantWriteGuard`, `Tenancy::Error`, `Tenancy::InconsistentContext`, `Tenancy::ProvisioningFailed`, `Tenancy::TenantMismatch`, `Tenancy::TenantIsImmutable` (fijado por `packs/platform/tenancy/spec/public_api_spec.rb`; packwerk impide usar el resto desde fuera).

**Barrera de escritura (`Tenancy::TenantWriteGuard`).** `acts_as_tenant` filtra lecturas y valida, pero `save(validate: false)` se salta las validaciones. `ApplicationRecord.acts_as_tenant` incluye en todo modelo tenant un guard en `before_save`/`before_destroy` que lanza `Tenancy::TenantMismatch` si `organization_id` no es el del tenant activo (crear o destruir en otra organización), `Tenancy::TenantIsImmutable` si se intenta cambiar el `organization_id` de un registro existente y `NoTenantSet` si se escribe sin tenant. La suite de aislamiento exige el guard y prueba los tres casos para cada modelo. Lo que no pasa por callbacks (`update_columns`, `update_all`, SQL crudo) lo cierra la barrera 2 (FK compuesta) y RLS (M4.03).

**Sin asociaciones que crucen tenants.** Una asociación cuya condición es `organization_id = <el de otro registro>` REEMPLAZA el scope del tenant: `Organization#companies` devolvía, desde el contexto A, las empresas de B (por eso se eliminó). Regla: ningún modelo raíz declara asociaciones hacia modelos tenant y ninguna asociación hacia un modelo tenant usa `organization_id` como clave foránea; los hijos se relacionan por la clave de su padre (`company_id`) dentro del tenant activo. Lo vigila `TenantIsolation.association_violations` (spec de aislamiento, con mensaje claro).

`Branch` convierte la violación de la FK compuesta en un error de validación (`errors[:company]`, "pertenece a otra organización") cuando alguien se salta las validaciones con `save(validate: false)`; el intento corre en un savepoint para no abortar la transacción del llamador. `update_columns` (que no pasa por el modelo) sí llega a la base, que lo rechaza con `fk_branches_company` (criterio 3).

## Contexto por request y por job

```ruby
Tenancy::Context = Data.define(:organization, :company, :branch, :principal)
Current.context  # un único objeto inmutable por request/job (Current vive en app/models/current.rb, pack raíz)

Tenancy.with_context(organization: org, company: co) { |context| ... }
```

- `Context` es inmutable (`Data`, congelado); cambiar de empresa crea uno nuevo (`context.with(company: otra)`). Valida la coherencia al construirse **y en cada `with`**: organización guardada, `company.organization_id == organization.id`, `branch.company_id == company.id` (y una sucursal exige empresa). Si no, `Tenancy::InconsistentContext`, **antes** de tocar el tenant o la base.
- **`Tenancy.with_context` es el único punto** que llama a `ActsAsTenant.with_tenant` y escribe `app.organization_id` (lo vigila el cop `Ceiba/TenantBypass`, ver abajo). Qué hace, en orden: construye y valida el `Context`; abre una **transacción** (`requires_new: true`, es decir, un savepoint si ya hay una: `SET LOCAL` solo existe dentro de una transacción); guarda el valor previo del setting; escribe el id con `set_config($1, $2, true)`; ejecuta el bloque con `ActsAsTenant.with_tenant` y `Current.set(context:)`; al terminar restaura el setting previo en un `ensure` **salvo que haya una excepción** (el rollback del savepoint ya lo revierte y, sobre una transacción abortada, cualquier sentencia fallaría y taparía el error original). Una salida no local (`return`, `break`, `throw`) libera el savepoint sin revertir el setting, por eso la restauración no puede depender de `rescue`.
- **Sin query cache:** el setting se lee y se escribe con `connection.uncached`. Rails activa la query cache en requests y jobs, y un `set_config` repetido servido desde la caché no se ejecutaría (el segundo `with_context(A)` dejaría el setting vacío y, anidado B→A, el de B bajo el tenant A). Cubierto en `with_context_spec.rb` (dentro de `ActiveRecord::Base.cache { }`) y por los specs de `return`/`break`.
- **Organización suspendida:** `with_context` acepta una organización `suspended`: el contexto es tenancy, no autorización. Si una request o un job debe rechazarla, lo decide M0.07 al resolver el contexto.
- Consecuencias que hay que conocer: (1) **si el bloque lanza, se revierte lo escrito dentro de él** (es una transacción) y el setting desaparece con ella, sin restauración manual; (2) un error de PostgreSQL que el bloque rescata **sin savepoint** deja la transacción abortada y `with_context` fallará al restaurar: aísla el intento con `transaction(requires_new: true)`; (3) cada contexto es una transacción: no envuelvas trabajo largo sin necesidad.
- Pruebas: `packs/platform/tenancy/spec/public/tenancy/with_context_spec.rb` (setting dentro/fuera, anidado, excepciones, parámetro enlazado) y `with_context_pool_spec.rb` (sin fixtures transaccionales: COMMIT real, otra conexión del pool no ve el setting, una conexión reutilizada llega sin contexto, dos hilos solapados con organizaciones distintas ven cada uno la suya).
- **Request:** la organización y la empresa salen de la **ruta** (`/api/v1/organizations/:organization_id/companies/:company_id/...`), nunca del body. Se validan contra los memberships del principal antes de fijar el contexto (M0.07/M0.08).
- **Job:** recibe `organization_id` (y los ids que necesite) como argumentos; el middleware de Sidekiq reconstruye el contexto con `Tenancy.with_context`. **Nunca se lee `Current` dentro de un job** (M0.10). **Ojo:** `acts_as_tenant` 2.2.2 instala por su cuenta una extensión de ActiveJob que serializa el tenant actual al encolar y lo restaura al ejecutar, **sin** pasar por `Tenancy.with_context` (no escribe `app.organization_id`). Hoy es inocuo (RLS está deshabilitado) pero M0.10/M4.03 deben reemplazarla por el middleware propio o desactivarla.

## Caminos privilegiados

| Caso | Cómo | Restricción |
| --- | --- | --- |
| Reportes consolidados de la organización | Dentro del tenant: no cruzan organizaciones, solo empresas | Solo conteos agregados, nunca datos personales |
| Back-office de plataforma | `Principal::PlatformStaff` + rol de BD con bypass | Cada acceso a datos de un tenant se audita; impersonación just-in-time con motivo y caducidad |
| Seeds, consola, migraciones de datos | `Tenancy.with_context` explícito por organización | Prohibido `ActsAsTenant.without_tenant` fuera de una allowlist revisada en CI |

**Guardia en CI: cop `Ceiba/TenantBypass`** (`backend/lib/rubocop/cop/ceiba/tenant_bypass.rb`, etapa `backend-lint`). Prohíbe en el código de aplicación (`app/`, `packs/*/*/app` y `lib`, `db`, `config` y los `*.rake`; los specs no se revisan) `ActsAsTenant.without_tenant`, `with_mutable_tenant`, `with_tenant`, `current_tenant=`, `unscoped=`, cualquier `.unscoped`, las otras formas de quitar la condición del tenant (`unscope(:where)`/`unscope(where: ...)`, `rewhere(organization_id: ...)`, `except(:where)`, `only(...)`), llegar a ellas con `send`/`public_send`/`__send__` y escribir en `ActsAsTenant::Current`. **No** cubre SQL crudo (`find_by_sql`, `connection.execute`): eso lo cierra RLS en M4.03. La única excepción inicial es `packs/platform/tenancy/app/public/tenancy.rb` (`with_context`). Un camino privilegiado nuevo (reporte consolidado, back-office) se añade a `AllowedFiles` en `backend/.rubocop.yml`, archivo por archivo y con revisión de CODEOWNERS; no se desactiva con `rubocop:disable`.

## Provisión de tenants

`Tenancy::ProvisionOrganization.call(organization:, company:, branch:)` es el **único** camino para crear una organización con su primera empresa y su primera sucursal; devuelve `Result(organization, company, branch)`.

- Una transacción (con savepoint si hay una externa, así un fallo no aborta al llamador). Claves desconocidas en cada sección → `ArgumentError`.
- Errores de **dominio**, no de BD: `Tenancy::ProvisioningFailed` con `code` (`:slug_reserved`, `:slug_taken`, `:invalid`), `message` legible en es-NI y `details` por sección y campo. La unicidad del slug la decide la **base** (`uq_companies_slug`): si dos provisiones compiten, ambas pasan la validación, gana la restricción UNIQUE y el perdedor recibe `:slug_taken` (probado con dos hilos, `provision_organization_call_spec.rb`).
- Altas posteriores: `Tenancy::AddCompany.call(organization:, **atributos)` y `Tenancy::AddBranch.call(company:, **atributos)` (misma traducción de errores y **la misma lista blanca de atributos** que la provisión: `id`, `status`, `organization_id`... lanzan `ArgumentError`); las usan los seeds y, más adelante, el back-office. Son API pública porque los modelos son privados.
- Hooks: `ProvisionOrganization.after_provision(callable = nil, key: nil, &block)` (devuelve el hook) y `.remove_after_provision(hook)`. Corren **en orden de registro, dentro de la transacción y dentro del contexto de la organización nueva** (`Current.context` con organización, empresa y sucursal) y reciben el `Result`. Un hook que lanza revierte todo y su error se propaga **tal cual** (los hooks corren fuera del traductor de errores de dominio: un `RecordInvalid` de un hook no se convierte en `ProvisioningFailed`). El registro vive en `Rails.application.config.x.tenancy` (no en un ivar de la clase, que se pierde al recargar en desarrollo) con un `Mutex`; registrar con la misma `key` reemplaza el hook, así que se registra desde `config.to_prepare { ProvisionOrganization.after_provision(MiHook, key: :access_owner) }` y es idempotente en cada recarga. **Pendiente para M0.08:** el playbook muestra un parámetro `owner:`; los hooks hoy solo reciben el `Result`, así que M0.08 deberá decidir cómo llegan los datos del dueño (p. ej. un parámetro `extras:` reenviado a los hooks).

Hooks previstos, que otros packs registran:

- `access`: crea el membership `org_owner` del usuario dueño.
- `modules`: activa los módulos por defecto según el plan (hoy, `appointments`).
- `notifications`: siembra las plantillas por defecto.

Ver [playbook de alta de organización](../playbooks/onboard-an-organization.md).

## Pruebas obligatorias

- **Suite de aislamiento genérica** (M0.05, `spec/platform/tenancy/isolation_spec.rb`; corre dentro de `rspec`, es decir, en `bin/ci backend-test`, no es un job opcional): `TenantIsolation.models` (`spec/support/tenant_isolation.rb`) descubre todos los `ApplicationRecord` cuya tabla tiene `organization_id` (por el esquema, no por una lista) y el ejemplo compartido `"un modelo tenant aislado"` verifica, para cada uno: (a) sin tenant `NoTenantSet`; (b) con A, ni las consultas ni el `count` incluyen filas de B; (c) un `find` de un id de B dentro de A lanza `RecordNotFound` (y a la inversa). **Cada modelo necesita una factory** que derive `organization_id` del tenant activo o del padre; si falta, los ejemplos **fallan** con "Falta una factory para X: agrega `factory :x, class: "X"`" (no se salta el modelo). Complementa al guardián de `platform/database` (tablas con `organization_id` == tablas con política) con `uncovered_tables`: toda tabla tenant debe tener un modelo (o una exención escrita en `TenantIsolation::UNMODELED_TABLES`). `tenant_isolation_spec.rb` demuestra el criterio 4 con una tabla tenant real efímera y un modelo sin factory.
- **Pruebas de bypass de RLS** (M4.03): con `acts_as_tenant` desactivado a propósito, una consulta SQL cruda no devuelve filas de otra organización.
- La autorización **entre empresas de la misma organización** se prueba en la matriz de autorización ([12](12-testing-strategy.md)), no aquí.

## Migración de un cliente grande a su propia base (salida prevista)

Gracias a los UUIDv7 (sin colisiones) y a que toda fila lleva `organization_id`, extraer una organización es una exportación filtrada por `organization_id` hacia otra instancia, más el enrutamiento de conexión por tenant (`connects_to` de Rails). No está planificado; solo se deja **posible**.
