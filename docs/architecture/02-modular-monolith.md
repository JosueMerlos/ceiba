# 02 — Monolito modular

> Decisión: [ADR-0001](../adr/0001-monolito-modular-packwerk.md). Hitos: M0.03, y cada hito que crea un pack.

## Por qué monolito modular

Un solo proceso y un solo despliegue (operación simple, transacciones locales, sin red entre módulos), con **límites internos verificados por herramienta**. Es la diferencia entre una casa de planta abierta, donde todo se mezcla, y una casa con paredes de carga: puedes remodelar una habitación sin derribar las demás.

Si algún día un módulo necesita escalar por separado, los límites ya existen y extraerlo es mecánico. Lo contrario (partir un monolito enredado) es un proyecto de meses.

## Capas

```
┌──────────────────────────────────────────────┐
│ modules/   appointments · billing · loyalty… │  Negocio. Dependen de platform.
│            Nunca dependen entre sí:          │  Se comunican SOLO por eventos.
├──────────────────────────────────────────────┤
│ platform/  identity · tenancy · access ·     │  Capacidades compartidas.
│            modules · events · audit ·        │  No conocen ningún módulo de negocio.
│            notifications · customers         │
├──────────────────────────────────────────────┤
│ app/ (raíz Rails)  ApplicationRecord,        │  Pegamento mínimo de Rails.
│            ApplicationController, config     │
└──────────────────────────────────────────────┘
```

| Pack | Responsabilidad | API pública (ejemplos) |
| --- | --- | --- |
| `platform/database` | Convenciones de BD: helpers de migración (`create_tenant_table`, `t.tenant_reference`, `enable_tenant_rls`), PK `uuidv7()`, registro de tablas tenant | `Database::TenantTables` (los helpers se instalan en el adaptador y se usan desde las migraciones, sin referencia a constantes) |
| `platform/identity` | Usuarios (personas), contraseñas, sesiones, 2FA, invitaciones | `Identity::Authenticate`, `Identity::CurrentSession` |
| `platform/tenancy` | Organización, empresa, sucursal, contexto, provisión | `Tenancy.with_context`, `Tenancy::ProvisionOrganization` |
| `platform/access` | Permisos, roles, memberships, principal, base de Pundit, API keys | `Access::Principal`, `Access::BasePolicy`, `Access.register_permissions` |
| `platform/modules` | Registro de manifiestos, `company_modules`, entitlements, settings | `Modules.registry`, `Modules.enabled?(company, key)`, `Modules.settings_for` |
| `platform/events` | Outbox, relay, suscripciones, consumidores idempotentes | `Events.publish`, `Events.subscribe` |
| `platform/audit` | `audit_events` append-only | `Audit.record` |
| `platform/notifications` | Canales (correo, WhatsApp), plantillas, consentimientos, delivery log | `Notifications.deliver`, `Notifications::Consent` |
| `platform/customers` | Cliente final, único **por empresa** | `Customers::FindOrCreate`, `Customers::Lookup` |
| `modules/appointments` | Servicios, profesionales, recursos, horarios, disponibilidad, citas | `Appointments::Book`, `Appointments::Availability` |

> `customers` vive en platform porque **todos** los módulos futuros (facturación, lealtad, historial) lo comparten. Si viviera en `appointments`, facturación tendría que depender de citas.

## Reglas (verificadas en CI)

1. **Dependencias declaradas.** Cada `package.yml` lista sus `dependencies`. Usar una constante de un pack no declarado es una violación.
2. **Capas** (layer checker de `packwerk-extensions`): `modules` puede depender de `platform`; `platform` **nunca** de `modules`. **Los módulos no dependen entre sí**: el layer checker permite dependencias dentro de la *misma* capa, así que esa regla la impone el **visibility checker** (cada módulo declara `enforce_visibility: true` y `visible_to: []`, es decir, ningún otro pack puede usarlo). Ver "Configuración real de Packwerk".
3. **Privacidad** (privacy checker de `packwerk-extensions`): de un pack solo se usa lo que está en `app/public/`. Modelos, controladores y servicios internos son privados.
4. **Sin `package_todo.yml` nuevo.** Las violaciones no se "aceptan para después"; CI falla si el archivo de deuda crece.
5. **Los modelos de otro pack no se tocan.** Para obtener datos de otro pack se usa su API pública (que devuelve objetos de valor o IDs), no sus modelos de ActiveRecord. Una asociación `belongs_to :customer` desde `appointments` es aceptable porque `customers` es una dependencia declarada de plataforma, **pero** las escrituras sobre el cliente pasan por `Customers::*`.

## Configuración real de Packwerk

Verificada en M0.03 contra las versiones fijadas: `packwerk 3.3.1`, `packwerk-extensions 0.4.0`, `packs-rails 0.1.1`. Packwerk 3 retiró el checker de privacidad del núcleo y lo movió a `packwerk-extensions`.

| Dónde | Clave | Valor |
| --- | --- | --- |
| `backend/packwerk.yml` | `require` | `packwerk/privacy/checker`, `packwerk/layer/checker`, `packwerk/visibility/checker` (se cargan los tres a mano en lugar de `packwerk-extensions` para no activar `folder_privacy`, que no usamos) |
| | `layers` | `[modules, platform]`, de la capa **más alta a la más baja** (`architecture_layers` es el nombre antiguo) |
| | `package_paths` | `"."` (pack raíz) y `"packs/*/*"` |
| `package.yml` de cada pack | `layer`, `enforce_dependencies`, `enforce_privacy`, `enforce_layers` | `layer` **explícito**: el layer checker solo lo infiere si la carpeta raíz del pack se llama como la capa, y aquí el pack se llama `packs/platform/x` |
| `package.yml` de un módulo | `enforce_visibility: true`, `visible_to: []` | Ningún otro pack puede usar un módulo |
| `package_todo.yml` | claves `layer` y `visibility` | Nombres de los tipos de violación (los de `architecture` están deprecados) |
| `backend/package.yml` | pack raíz | Sin capa y sin enforcement: cualquier pack puede depender de él declarando `"."` (los packs generados lo declaran, usan `ApplicationRecord`) |

Diferencias respecto de lo que decía este documento:

- **Los módulos entre sí no los frena el layer checker** sino el visibility checker (el layer checker permite la misma capa). Un módulo que usa a otro sin declararlo falla por **dependencia y visibilidad**; si lo declara, falla por **visibilidad** (no por capas). Si además es `platform` → `modules`, falla por **capas**.
- `packwerk validate` también rechaza los ciclos de dependencias: un `platform` que *declare* depender de un módulo (que a su vez depende de él) ni siquiera valida.
- `packs-rails` carga `app/*` de cada pack (incluido `app/public`), `config/locales`, `config/initializers` y `lib`, pero **no `db/migrate`**: `config/application.rb` lo registra en `paths["db/migrate"]` (lo leen las tareas rake) y `config/initializers/packs_migrations.rb` asigna `ActiveRecord::Migrator.migrations_paths` (lo leen `check_all_pending!`, `maintain_test_schema!` y el aviso de migraciones pendientes de desarrollo). `.rspec` lleva `--require packs/rails/rspec` para que `rspec` corra también los specs de `packs/*/*/spec`.
- Las rutas de `controllers` pueden colgar de `Api::V1::<Pack>` (`app/controllers/api/v1/<pack>/`, como en la estructura de abajo). Es la única excepción a "namespace = pack" y la admite el cop `Ceiba/PackNamespace`.
- `packwerk.yml` excluye `spec/` y `lib/` de la raíz, `packs/*/*/spec/**` y `manifest.rb` (el manifiesto referencia constantes de plataforma por diseño y se valida con su propio registro en M0.09).
- Los controladores `health` y `ready` **se quedan en la raíz** (`backend/app/controllers`): son infraestructura de Rails (sondas de Docker/proxy, M0.01), no una capacidad de plataforma de las listadas arriba. Moverlos habría creado un pack artificial sin dominio.
- Los cops de rubocop-rails limitados a `app/models`, `app/controllers`... (`Rails/EnumHash`, `Rails/InverseOf`, `Rails/LexicallyScopedActionFilter`) se amplían a `**/app/...` para cubrir los packs. Los demás cops de rubocop-rails con `Include: app/**` siguen sin revisar los packs: pendiente de ampliar cuando haya código real en packs.

### Cómo se cablea la plataforma con los módulos (M0.09)

Con `visible_to: []` **nadie** puede referenciar una constante de un módulo, ni siquiera `platform/modules` ni el pack raíz `.`. Es intencional y M0.09 debe diseñarse **dentro** de esa restricción, no abriéndola:

- **El registro descubre, no referencia.** `platform/modules` carga `packs/modules/*/manifest.rb` con `Dir.glob` + `load`/`instance_eval`: es lectura de archivos, no una referencia a constantes que Packwerk vea (y `manifest.rb` está excluido de Packwerk). El DSL `Modules.define` vive en `platform/modules`, que el módulo sí puede usar (dependencia `modules` → `platform`).
- **Los puntos de extensión del módulo se declaran como cadenas**, no como constantes: `on_enable "Appointments::Lifecycle::OnEnable"`, suscriptores y navegación se resuelven con `constantize` en tiempo de ejecución desde la plataforma. Packwerk no ve `constantize`, así que la plataforma sigue sin conocer a ningún módulo estáticamente (es el límite conocido del análisis estático, ADR-0001).
- **Rutas:** cada pack aporta su archivo de rutas; el `config/routes.rb` raíz usa `draw(:nombre)` (packs-rails), que son nombres de archivo, no constantes.
- **Los módulos se comunican por eventos** (`platform/events`), nunca por llamadas directas.
- **Si algo de lo anterior resultara imposible**, la salida no es relajar el package.yml del módulo sino una **allowlist explícita y mínima** en `PackContract::ALLOWED_VISIBLE_TO` (`lib/ci/pack_contract.rb`), pack por pack (por ejemplo `{ "packs/modules/appointments" => ["packs/platform/modules"] }`), revisada por los CODEOWNERS. El spec global de contrato falla ante cualquier `visible_to` que no coincida exactamente con esa lista.

### Quién protege el aislamiento

El aislamiento entre módulos depende de `package.yml`, así que se protege en tres niveles: (1) `spec/packs/pack_contract_spec.rb` recorre **todos** los `packs/*/*` reales y falla si falta un `package.yml`, si la capa no coincide con la carpeta, si un `enforce_*` no es `true`, o si un módulo no tiene `enforce_visibility: true` y `visible_to` exactamente igual a la allowlist; (2) `.github/CODEOWNERS` exige revisión del dueño (`@JosueMerlos`, placeholder) sobre `packs/**/package.yml`, `packwerk.yml`, `package.yml` raíz y el propio contrato (hace falta activar "Require review from Code Owners" en la rama protegida cuando haya más de una persona); (3) el spec base del pack generado.

### Cómo se verifica

| Qué | Dónde |
| --- | --- |
| `packwerk validate` + `packwerk check` | `backend/bin/ci-packs` (job `backend-packs`, etapa `bin/ci backend-packs`) |
| `package_todo.yml` no crece | `infra/scripts/check-package-todo-growth.sh`, con sus casos en `..._test.sh`. Compara con el **merge-base** de la rama destino: en un PR `origin/<destino>` (CI exporta `BASE_REF`), en un push a `main` el SHA anterior, en local `main`. Cuenta líneas *agregadas* (incluye archivos nuevos y cambios sin commitear) |
| Namespace = pack | cop `Ceiba/PackNamespace` (`backend/lib/rubocop/cop/ceiba/`), en `backend-lint`: cada módulo/clase definido en un pack (resolviendo el anidamiento; `::X` es absoluto) debe quedar dentro del namespace del pack |
| Carga (Zeitwerk, `app/*`, `db/migrate`) | `spec/packs/generated_pack_spec.rb`: genera un pack en una **copia temporal** de la app, en un proceso nuevo, y hace `eager_load!`; comprueba además que `migration_context` ve la migración del pack y que `check_all_pending!` la detecta (ver `config/initializers/packs_migrations.rb`); en CI `CI=true` activa además el eager load de toda la app |

## Estructura de un pack

```
packs/modules/appointments/
  package.yml                 dependencias, capa, enforce_privacy
  manifest.rb                 manifiesto del módulo (solo packs de modules/, ver 05)
  app/
    public/appointments/      API pública: servicios de entrada, value objects, eventos
    models/appointments/
    services/appointments/
    controllers/api/v1/appointments/
    policies/appointments/
    serializers/appointments/
    jobs/appointments/
    subscribers/appointments/ consumidores de eventos de otros packs
  db/migrate/                 migraciones propias del pack
  config/locales/es-NI.yml
  spec/
```

- Se usa `packs-rails` para que Rails cargue `app/*` y `db/migrate` de cada pack.
- Namespace Ruby = nombre del pack (`Appointments::`), sin excepción.
- Rutas: cada pack aporta su archivo de rutas montado bajo `/api/v1`; el registro de módulos condiciona su acceso ([05](05-module-system.md)).

## Comunicación entre packs

| Necesidad | Mecanismo | Ejemplo |
| --- | --- | --- |
| Un módulo usa una capacidad de plataforma | Llamada síncrona a la API pública | `Customers::FindOrCreate.call(company:, phone:)` |
| Un módulo reacciona a algo de otro módulo | **Evento** vía outbox | `billing` escucha `appointments.appointment_completed.v1` |
| La plataforma necesita algo de un módulo | **Inversión**: el módulo se registra (manifiesto, hooks) | `appointments` registra sus permisos en `access` |

Prohibido: que un módulo llame a un servicio de otro módulo, o que lea sus tablas.

## Generador de packs

`bin/rails g pack <capa>/<nombre>` (`platform/identity`, `modules/billing`) crea la estructura, `package.yml` con la capa y los checkers activos, un archivo de locales y un spec base que valida el contrato del pack (`spec/support/pack_contract.rb`); para `modules/` además un `manifest.rb` **placeholder** (su contenido y los specs de manifiesto válido y permisos registrados llegan con M0.09). Rechaza capas y nombres inválidos (snake_case, no reservados), packs existentes y nombres ya usados en la otra capa (el namespace es único). Así cada módulo nuevo empieza **cumpliendo** las reglas ([playbook](../playbooks/add-a-module.md)).

## Anti-patrones a vigilar

| Anti-patrón | Señal | Corrección |
| --- | --- | --- |
| `platform` como cajón de sastre | Packs de plataforma con lógica de un solo módulo | Si solo un módulo lo usa, vive en ese módulo |
| Pack "shared"/"utils" | Todo depende de él | Distribuir en el pack dueño o en `app/` si es infraestructura Rails pura |
| API pública demasiado ancha | `app/public` exporta modelos | Exportar servicios y value objects |
| Eventos usados como RPC | Un evento espera respuesta | Si se necesita respuesta, es una llamada síncrona a plataforma o el diseño está mal |
