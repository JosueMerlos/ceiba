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
2. **Capas** (layer checker de `packwerk-extensions`): `modules` puede depender de `platform`; `platform` **nunca** de `modules`; los módulos no dependen entre sí.
3. **Privacidad** (privacy checker de `packwerk-extensions`): de un pack solo se usa lo que está en `app/public/`. Modelos, controladores y servicios internos son privados.
4. **Sin `package_todo.yml` nuevo.** Las violaciones no se "aceptan para después"; CI falla si el archivo de deuda crece.
5. **Los modelos de otro pack no se tocan.** Para obtener datos de otro pack se usa su API pública (que devuelve objetos de valor o IDs), no sus modelos de ActiveRecord. Una asociación `belongs_to :customer` desde `appointments` es aceptable porque `customers` es una dependencia declarada de plataforma, **pero** las escrituras sobre el cliente pasan por `Customers::*`.

> Nota de verificación: Packwerk 3 retiró el checker de privacidad del núcleo y lo movió a `packwerk-extensions`, que además incluye el checker de capas. Al implementar M0.03, confirmar los nombres exactos de configuración en la versión vigente.

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

`bin/rails g pack modules/<nombre>` crea la estructura, `package.yml` con la capa correcta, un `manifest.rb` con los campos obligatorios vacíos, un archivo de locales y specs base (manifiesto válido, permisos registrados). Así cada módulo nuevo empieza **cumpliendo** las reglas ([playbook](../playbooks/add-a-module.md)).

## Anti-patrones a vigilar

| Anti-patrón | Señal | Corrección |
| --- | --- | --- |
| `platform` como cajón de sastre | Packs de plataforma con lógica de un solo módulo | Si solo un módulo lo usa, vive en ese módulo |
| Pack "shared"/"utils" | Todo depende de él | Distribuir en el pack dueño o en `app/` si es infraestructura Rails pura |
| API pública demasiado ancha | `app/public` exporta modelos | Exportar servicios y value objects |
| Eventos usados como RPC | Un evento espera respuesta | Si se necesita respuesta, es una llamada síncrona a plataforma o el diseño está mal |
