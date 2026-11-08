# Ceiba — Documentación

> **Fuente única de verdad del proyecto.** Lo que no está aquí no está decidido.
> Los documentos de [`../plans/`](../plans/) son **históricos**: sirvieron para llegar hasta aquí y su contenido válido se migró a esta carpeta.
> Última actualización: 2026-11-07

## Cómo leer esta documentación

| Si quieres… | Lee |
| --- | --- |
| Entender qué construimos y para quién | [`00-vision.md`](00-vision.md) |
| Saber qué sigue y en qué estado está cada pieza | [`roadmap/README.md`](roadmap/README.md) |
| Ejecutar el siguiente paso | El primer hito `pendiente` de la hoja de ruta, en [`milestones/`](milestones/README.md) |
| Entender **cómo** está construido | [`architecture/`](architecture/01-overview.md) (empezar por 01) |
| Saber **por qué** se decidió algo | [`adr/`](adr/README.md) |
| Agregar un módulo o dar de alta una organización | [`playbooks/`](playbooks/add-a-module.md) |
| Entender el vocabulario del negocio | [`domain/glossary.md`](domain/glossary.md) |

## Índice

| Documento | Contenido |
| --- | --- |
| [`00-vision.md`](00-vision.md) | Visión, mercado (Nicaragua), principios, modelo de negocio |
| **Arquitectura** | |
| [`01-overview`](architecture/01-overview.md) | C4 de contexto y contenedores, stack, flujo de una request |
| [`02-modular-monolith`](architecture/02-modular-monolith.md) | Packs, capas, API pública, reglas de Packwerk |
| [`03-multi-tenancy`](architecture/03-multi-tenancy.md) | Tenant = organización; las tres barreras (acts_as_tenant, FKs compuestas, RLS) |
| [`04-access-control`](architecture/04-access-control.md) | Principal, permisos como datos, memberships, matriz corregida, operador de plataforma |
| [`05-module-system`](architecture/05-module-system.md) | Manifiesto, activación, settings, entitlements vs flags |
| [`06-events-and-jobs`](architecture/06-events-and-jobs.md) | Outbox, relay, idempotencia, escáneres |
| [`07-api-contract`](architecture/07-api-contract.md) | Rutas, problem+json, cursor, idempotencia, cliente TS generado |
| [`08-frontend`](architecture/08-frontend.md) | Workspace, panel, booking, `AgendaView`, branding |
| [`09-data-conventions`](architecture/09-data-conventions.md) | UUIDv7, tablas tenant, tiempo, dinero, PII, borrado, índices |
| [`10-infrastructure`](architecture/10-infrastructure.md) | Entornos, CI, Kamal, backups, observabilidad |
| [`11-security`](architecture/11-security.md) | Credenciales, sesiones, CSRF, rate limiting en dos capas, cabeceras |
| [`12-testing-strategy`](architecture/12-testing-strategy.md) | Pirámide y las 6 suites de plataforma |
| [`13-privacy-ley-787`](architecture/13-privacy-ley-787.md) | Ley 787: consentimientos, derechos, checklist legal |
| **Dominio** | [glosario](domain/glossary.md) · [citas](domain/appointments.md) |
| **Playbooks** | [agregar un módulo](playbooks/add-a-module.md) · [dar de alta una organización](playbooks/onboard-an-organization.md) |
| **Decisiones** | [30 ADRs](adr/README.md) |
| **Hoja de ruta** | [roadmap](roadmap/README.md): 5 fases y 33 hitos detallados (F0–F4) |
| **Plantillas** | [hito](templates/milestone.md) · [ADR](templates/adr.md) |

## Decisiones de la sesión del 2026-11-07

| Tema | Decisión | ADR |
| --- | --- | --- |
| Motor de BD | PostgreSQL 18 (evaluado frente a MySQL) | [0002](adr/0002-postgresql-18.md) |
| Jobs | Sidekiq + Redis con **outbox propio** | [0009](adr/0009-sidekiq-con-outbox.md) |
| Row Level Security | Preparado desde el día 0; **activado antes de los pilotos** (M4.03) | [0005](adr/0005-rls-preparado-activado-en-piloto.md) |
| Reserva pública | App React ligera aparte (`apps/booking`), mismo origen | [0015](adr/0015-reserva-publica-app-separada.md) |
| Identificadores | UUIDv7 en todas las tablas | [0006](adr/0006-uuidv7-como-clave-primaria.md) |
| Calendario | Librería gratuita detrás de `AgendaView` | [0014](adr/0014-calendario-gratuito-con-adaptador.md) |
| Mercado | Solo Nicaragua (Ley 787, NIO/USD, WhatsApp) | [0024](adr/0024-mercado-nicaragua.md) |
| Permisos | Permisos como datos declarados por los módulos | [0008](adr/0008-permisos-como-datos.md) |
| Módulos | Manifiesto + activación por empresa + entitlements separados | [0010](adr/0010-modulos-por-empresa-y-manifiesto.md) |
| Ritmo | 8–15 h/semana → hitos de ≤ 15 h | [roadmap](roadmap/README.md) |
| Nombre | **Ceiba** (dominio y marca por verificar) | [0030](adr/0030-nombre-del-producto-ceiba.md) |

**Decisiones pendientes con fecha:** BD gestionada vs autogestionada y proveedores de infraestructura → M4.04; router del frontend → M0.12; librería de calendario → M2.02; pasarela de cobro → F6.

## Correcciones respecto a `plans/`

1. RLS "opcional" vs "descartado" → preparado y activado en M4.03 ([ADR-0005](adr/0005-rls-preparado-activado-en-piloto.md)).
2. Página pública "server-rendered" vs SPA → `apps/booking` separada, mismo origen ([ADR-0015](adr/0015-reserva-publica-app-separada.md)).
3. La matriz no daba branding a `org_admin`, contra la decisión tomada → corregido en [04](architecture/04-access-control.md).
4. LFPDPPP (México) → **Ley 787 (Nicaragua)** ([13](architecture/13-privacy-ley-787.md)).
5. `UserRole(scope_id)` sin tipo ni FKs → `memberships` con columnas explícitas y CHECK ([ADR-0008](adr/0008-permisos-como-datos.md)).
6. Un spec mezclaba aislamiento de tenant y autorización por empresa → dos suites ([12](architecture/12-testing-strategy.md)).
7. "Encolar después del commit" no es un outbox con Sidekiq → `outbox_events` ([ADR-0009](adr/0009-sidekiq-con-outbox.md)).
8. Notificaciones dentro de `appointments` → `platform/notifications` ([ADR-0023](adr/0023-notificaciones-como-plataforma.md)).
9. Rack::Attack con claves `user_id` antes de autenticar → dos capas ([ADR-0027](adr/0027-rate-limiting-en-dos-capas.md)).
10. Faltaba el operador de plataforma → `PlatformStaff` + back-office (M4.01).
11. Entitlement, activación y flag mezclados → separados ([05](architecture/05-module-system.md)).
12. Prefijo de API key `ok_live_` → `cb_live_` / `cb_test_` (prefijo de Ceiba; distingue los entornos).

## Trazabilidad de decisiones previas

Cada decisión cerrada en `plans/` y dónde vive ahora.

### `plan-ecosistema-modular-pendientes.md` §5 (11 decisiones)

| # | Decisión | Ahora en |
| --- | --- | --- |
| 1 | Branding: columnas en `companies` | [ADR-0025](adr/0025-branding-en-companies.md) |
| 2 | Branding: editor `company_manager` + `org_admin` | [ADR-0025](adr/0025-branding-en-companies.md), [04 §Matriz](architecture/04-access-control.md) |
| 3 | URL pública `/c/:slug` | [ADR-0025](adr/0025-branding-en-companies.md), [08](architecture/08-frontend.md) |
| 4 | Tipografía: 3 curadas | [ADR-0025](adr/0025-branding-en-companies.md) |
| 5 | Persona separada del profesional; asignación por sucursal | [ADR-0020](adr/0020-persona-separada-de-profesional.md) |
| 6 | `branch_manager` no edita precios | [04 §Matriz](architecture/04-access-control.md) |
| 7 | `org_admin` solo conteos; soporte just-in-time | [04](architecture/04-access-control.md) |
| 8 | Invitaciones sin doble aprobación | [04 §Matriz](architecture/04-access-control.md), M4.01 |
| 9 | Usuario en varias organizaciones | [ADR-0028](adr/0028-usuario-multi-organizacion.md) |
| 10 | Facturación a la organización por sucursal activa | [ADR-0026](adr/0026-facturacion-a-la-organizacion.md) |
| 11 | Prorrateo y piloto de 3 meses | [ADR-0026](adr/0026-facturacion-a-la-organizacion.md) |

### `plan-ecosistema-modular-seguridad.md` §8 (6 decisiones)

| # | Decisión | Ahora en |
| --- | --- | --- |
| 1 | Sesión del panel en BD revocable | [ADR-0017](adr/0017-sesiones-en-bd-sin-devise.md) |
| 2 | Contraseñas de 12+ caracteres + HIBP | [11](architecture/11-security.md), M4.02 |
| 3 | 2FA obligatorio para `org_owner`/`org_admin` | [11](architecture/11-security.md), M4.02 |
| 4 | Scopes de API key `read:`/`write:` por módulo | [11](architecture/11-security.md), [05](architecture/05-module-system.md) |
| 5 | Tabla de límites como default, configurable por ENV | [11](architecture/11-security.md), [ADR-0027](adr/0027-rate-limiting-en-dos-capas.md) |
| 6 | Throttling visible en logs + Sentry | [11](architecture/11-security.md), M0.13 |

### `plan-ecosistema-modular-pendientes.md` §6 ("no reabrir sin motivo")

| Decisión | Ahora en |
| --- | --- |
| Jerarquía Organización → Empresa → Sucursal | [ADR-0004](adr/0004-jerarquia-organizacion-empresa-sucursal.md) |
| Cliente único por empresa | [ADR-0021](adr/0021-cliente-unico-por-empresa.md) |
| Tenant = organización | [ADR-0003](adr/0003-tenant-es-la-organizacion.md) |
| `company_modules(company_id, module_key, …)` | [ADR-0010](adr/0010-modulos-por-empresa-y-manifiesto.md) |
| El giro no es un módulo | [ADR-0011](adr/0011-el-giro-no-es-un-modulo.md) |
| Citas con `appointment_services` | [ADR-0029](adr/0029-citas-multi-servicio.md) |
| Buffer como `blocks_from`/`blocks_to` | [ADR-0018](adr/0018-integridad-de-agenda-en-bd.md) |
| Constraints separadas para profesional y recurso | [ADR-0018](adr/0018-integridad-de-agenda-en-bd.md) |
| Reprogramación con `FOR UPDATE` + `WHERE status` | [ADR-0019](adr/0019-reprogramar-crea-cita-nueva.md) |
| RBAC como datos con alcance | [ADR-0008](adr/0008-permisos-como-datos.md) |
| `audit_events` append-only + `idempotency_key` | [ADR-0022](adr/0022-auditoria-append-only-e-idempotencia.md) |
| Un único punto de entrada `Appointments::Book` | [ADR-0018](adr/0018-integridad-de-agenda-en-bd.md) |

### Otras decisiones de `plans/` migradas

| Decisión | Ahora en |
| --- | --- |
| Monolito modular con Packwerk | [ADR-0001](adr/0001-monolito-modular-packwerk.md) |
| Pundit, no CanCanCan | [ADR-0007](adr/0007-pundit-sobre-cancancan.md) |
| Credenciales por superficie; JWT solo para la app móvil | [ADR-0016](adr/0016-credenciales-por-superficie.md) |
| Backlog P1/P2/P3 de pendientes §4 | P1 → hitos de F0–F4; P2 → F5; P3 → futuro ([roadmap](roadmap/README.md)) |
