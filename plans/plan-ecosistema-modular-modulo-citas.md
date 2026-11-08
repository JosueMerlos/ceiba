> **HISTÓRICO, no es fuente de verdad.** Desde el 2026-11-07, la documentación vigente vive en [`../docs/`](../docs/README.md). Este archivo se conserva como registro de cómo se llegó a las decisiones; su contenido válido se migró a `docs/` y sus inconsistencias se corrigieron allí (ver `docs/README.md` § Correcciones).

# Plan del ecosistema modular: módulo de citas (revisado)

Plan de trabajo · 6 de noviembre de 2026

## 1. Visión

Construir un ecosistema de módulos integrados que puedan usar tanto negocios individuales como franquicias. El primer módulo es el de citas, dirigido a pequeñas empresas de servicios (clínicas dentales, salones de belleza, barberías, consultorios). Los módulos siguientes (facturación, inventario, lealtad, historial clínico) se construyen sobre la misma base, sin rehacerla.

El proyecto se desarrollará en tiempo libre, por lo que el plan prioriza decisiones simples de operar, pocos servicios en producción y validación temprana con negocios reales.

## 2. Stack y entorno

- **Backend:** Ruby on Rails en modo API, con PostgreSQL.
- **Frontend:** React con TypeScript (Vite), TanStack Query para el estado del servidor y FullCalendar para la agenda.
- **Trabajos en segundo plano:** Sidekiq con Redis, para recordatorios y notificaciones.
- **Docker desde el inicio:** servicios separados para base de datos, Redis, API, worker, frontend y un servidor de correo de desarrollo (Mailpit). Todo el entorno se levanta con un solo comando y no requiere instalar Ruby ni Node localmente.
- **Producción (más adelante):** imagen Docker multi-etapa, CI con GitHub Actions y despliegue con Kamal a un VPS, sin necesidad de Kubernetes al principio.

## 3. Arquitectura

**Monolito modular con Packwerk.** Un solo despliegue, con módulos aislados internamente en `packs/`. Packwerk valida en CI que ningún módulo dependa de otro de forma indebida.

- `core`: base compartida. No depende de ningún otro módulo.
- `appointments`: módulo de citas. Depende únicamente de `core`.
- Módulos futuros: declaran su dependencia de `core` y se enteran de lo que ocurre en citas mediante eventos (por ejemplo, "cita completada"), nunca importando clases de otro módulo.

**Multi-tenancy:** una sola base de datos con identificador de organización en cada tabla (gema acts_as_tenant), con políticas de acceso por rol (Pundit). Opcionalmente se agrega Row Level Security en PostgreSQL como segunda capa. Si un cliente grande lo requiere, se puede migrar a una base separada más adelante.

**Alcance del tenant (revisado):** el tenant de `acts_as_tenant` es la **organización**: es la frontera dura entre clientes y la que se propaga a los jobs. Empresa y sucursal no son tenants; son alcances de autorización que viven en `Current.context` y se verifican con Pundit. Los reportes consolidados de la organización son el **único** camino privilegiado y deben ser explícitos en el código, nunca un `unscoped` suelto.

**Módulos activados por empresa (revisado):** la organización define la marca y el cobro; la **empresa** es la unidad que activa módulos. Tabla `company_modules(company_id, module_key, enabled_at, settings)`, con índice único en `(company_id, module_key)`:

- `module_key` es un identificador estable (`appointments`, `clinical_records`, `billing`, `inventory`, `loyalty`); nunca un booleano por módulo en la tabla de empresas.
- `settings` (jsonb) guarda la configuración del módulo para esa empresa.
- Un módulo desactivado desaparece de la navegación y de la API para esa empresa, y además se verifica en Pundit. Ocultarlo en el frontend no es control de acceso.
- El **giro** (clínica dental, salón de belleza) no es un módulo: es configuración del módulo de citas. Un salón y una clínica comparten el MISMO pack `appointments`; lo que cambia son sus servicios, su branding y los módulos adicionales que tengan activos.
- Ningún módulo se habilita a nivel organización: se habilita por empresa, porque es ahí donde vive el negocio real.

**Jerarquía de la organización (revisado):** Organización (marca o franquicia) → Empresa/Negocio → Sucursal → Profesionales y recursos.

- **Organización:** contiene una o varias empresas. Es el nivel de administración global y de facturación; agrupa los reportes consolidados.
- **Empresa/Negocio:** unidad con giro propio (clínica dental, salón de belleza), su marca (colores, logos, banners), catálogo de servicios, profesionales y clientes.
- **Sucursal:** ubicación física de una empresa, con su propia zona horaria (IANA), horarios de atención y recursos.
- **Profesionales y recursos:** pertenecen a una empresa y se asignan a una o más sucursales de esa empresa. Cada profesional referencia a una **persona** (usuario), que puede ser profesional de varias empresas del grupo con registros separados.
- Un negocio pequeño es una organización con una sola empresa y una sola sucursal; la interfaz colapsa los tres niveles en uno.
- Una franquicia es una organización con varias empresas (una por marca) y varias sucursales por empresa.

| Nivel | Qué define | Qué NO define |
| --- | --- | --- |
| Organización | Marca o franquicia, plan de suscripción, administradores globales, reportes consolidados | Servicios, precios, horarios, zona horaria |
| Empresa/Negocio | Giro, branding (colores, logo, banners), catálogo de servicios, profesionales, clientes | Zona horaria, horarios de atención, recursos físicos |
| Sucursal | Zona horaria IANA, horarios de atención, recursos (sillas, salas), agenda | Catálogo de servicios (solo override), precios base, clientes |
| Profesional/Recurso | Horario semanal, ausencias, citas, sucursales donde atiende | Precio base del servicio (solo override) |

**Reglas duras de la jerarquía:**

- Un **profesional** nunca cruza empresas: su registro (horario, servicios, citas) vive en una sola empresa. La **persona** detrás del profesional (usuario) sí puede servir en varias empresas del grupo, con un registro profesional por empresa. Caso típico: un especialista que atiende 2 días por semana en dos sucursales de una empresa y el resto en otra del mismo grupo.
- El cliente es único por **empresa**, no por organización. No se comparte entre empresas del mismo grupo (privacidad y giros distintos). Los reportes consolidados solo agregan conteos, nunca datos personales.
- Los servicios viven a nivel **empresa**; una sucursal puede sobrescribir duración o precio, pero no crear servicios propios.
- La zona horaria se define únicamente en la **sucursal**. Todo se guarda en UTC y se muestra en la zona de la sucursal, nunca la del navegador.
- Los roles tienen alcance: organización, empresa o sucursal.
- **Migración:** `company_id` obligatorio en `services`, `professionals`, `clients` y `appointments`; `branch_id` sigue siendo obligatorio en `appointments`.

**Autenticación:** sesión por cookie httpOnly entre el frontend y la API. Se evita guardar tokens en el navegador, salvo que una app móvil futura lo requiera.

> Políticas de seguridad API-first (API keys, JWT condicionado, Rack::Attack, principal para Pundit): ver [`plan-ecosistema-modular-seguridad.md`](plan-ecosistema-modular-seguridad.md).

## 4. Modelo de datos (visión general)

**Módulo core**

- Organizaciones, empresas, sucursales (con su zona horaria), usuarios, membresías (rol por organización, empresa o sucursal) y clientes.
- El cliente es único por empresa y lo reutilizarán todos los módulos futuros.
- **Módulos por empresa:** `CompanyModule(company_id, module_key, enabled_at, settings)` vive en `core`, no en cada pack. Cada pack consulta si su propio módulo está activo antes de registrar rutas, encolar jobs o autorizar acciones.

**Módulo appointments**

- Servicios: duración, tiempo de preparación o limpieza (buffer) y precio.
- **Citas con varios servicios:** una cita agrupa uno o más servicios mediante `appointment_services`, que congela la duración y el precio vigentes al reservar. La duración total de la cita es la suma de sus servicios; el motor de disponibilidad siempre calcula sobre ese total.
- Profesionales y recursos: una silla o sala se reserva igual que una persona y tiene su **propia** restricción de exclusión por `resource_id`, no solo la del profesional.
- Horarios semanales, ausencias y días libres.
- Citas, con estado y origen (staff, página pública, WhatsApp).

**Estados de la cita (revisado)**

- Flujo normal: `scheduled → confirmed → checked_in → completed`.
- Estados alternos: `cancelled`, `no_show`, `rescheduled`.
- Las transiciones válidas se definen en una tabla o en un servicio de dominio; nunca se actualiza `status` a mano desde el controlador.
- **Reprogramar** no muta la cita existente: crea una cita nueva con `rescheduled_from_id` y marca la anterior como `rescheduled`. Así se conserva el historial y la auditoría.
- La reprogramación es **segura ante concurrencia**: se bloquea la cita original (`SELECT … FOR UPDATE`) y el cambio de estado se hace con `WHERE status = 'scheduled'`, verificando las filas afectadas. Si dos personas reprograman a la vez, la segunda recibe `409`, no una segunda cita nueva.
- `Appointments::Reschedule` orquesta el cambio y delega la creación en `Appointments::Book`; no existe otro camino que cree citas.

**Roles y alcance (revisado)**

- RBAC como datos, no como condicionales dispersos:
  - `Role(nombre, scope: :organization | :company | :branch)`
  - `UserRole(user_id, role_id, scope_id)`
- `Pundit` consulta los roles del usuario en el contexto actual, nunca `current_user.admin?` esparcido por el código.
- `Current.context = Context.new(user:, organization:, company:, branch:)`. El contexto se construye una sola vez por solicitud; el resto del código lee de ahí y nunca de `params` sueltos.

**Auditoría e idempotencia (revisado)**

- **Auditoría:** tabla append-only `audit_events(actor_id, action, auditable_type, auditable_id, before, after, created_at)`. Sin updates ni deletes, incluso para administradores.
- **Idempotencia:** `idempotency_key` único por organización en la creación de citas y en el envío de recordatorios, para que un reintento de red o un doble clic no genere duplicados.

**Reglas críticas**

- Todas las fechas se guardan en UTC y se muestran según la zona horaria de la sucursal, no la del navegador.
- La doble reserva se impide en la base de datos mediante una restricción de exclusión sobre el intervalo **efectivo** de cada recurso. Ese intervalo se guarda ya calculado en `blocks_from` y `blocks_to` (incluye los buffers antes y después), de modo que cambiar un servicio en el futuro no altera el significado del historial. No se confía solo en validaciones del frontend.
- Toda cita se crea por un único punto de entrada (`Appointments::Book` o equivalente), que traduce el conflicto en un error claro (horario ya no disponible) y responde `409`, nunca `500`. La reprogramación pasa por `Appointments::Reschedule`, que invoca a `Book`; ningún controlador crea citas directamente.
- El mismo humano puede ser profesional de varias empresas del grupo (persona compartida, registros separados). Además de la restricción por `professional_id`, `Appointments::Book` valida que la persona no tenga otra cita, en ninguna empresa del grupo, en el mismo rango: la restricción de BD cubre registros, no personas.

## 5. Alcance del MVP

Incluido:

- Catálogo de servicios.
- Profesionales con horarios, descansos y días libres.
- Agenda con vista de calendario para el staff.
- Página pública de reservas por negocio (`/c/:slug` en el dominio de la plataforma), con enlace compartible para Instagram y WhatsApp.
- Recordatorios automáticos por correo y WhatsApp.
- Cancelación y reprogramación por parte del cliente.
- Registro de ausencias.

Excluido por ahora: pagos, facturación, inventario, historial clínico, sincronización con calendarios externos.

## 6. Hoja de ruta por fases

Cada fase se planifica en bloques de aproximadamente dos semanas y termina con una demo funcional, aunque sea interna.

**Fase 0: Fundaciones**

- Entorno Docker funcionando y apps Rails y React creadas.
- Packwerk configurado, con su verificación en CI.
- Packs core y appointments con sus migraciones.
- `company_modules` en core, con `appointments` activado por defecto para toda empresa nueva.
- Autenticación, tenant actual por solicitud y pruebas básicas.
- **Definición de terminado:** `docker compose up` levanta todo en una máquina limpia; CI corre Packwerk y los tests; existe login y una página protegida que responde con datos del tenant actual.

**Fase 1: Motor de disponibilidad**

- Cálculo de huecos libres a partir de horarios, ausencias y citas existentes, en la zona horaria de la sucursal.
- **Contrato del motor:** entrada `company`, `branch`, `services` (lista), `professional | :any`, rango de fechas y zona IANA; salida `[{ starts_at_utc, duration, price, professional_id }]`, con `duration` y `price` ya totalizados a partir de todos los servicios.
- Buffers antes y después configurables por servicio.
- Anticipación mínima (~2 h) y máxima (~60 días) configurables.
- `:any` devuelve el primer hueco libre entre todos los profesionales elegibles de la empresa en esa sucursal.
- Probar el horario de verano (DST) aunque el primer mercado no lo use.
- Fuera del MVP: capacidad mayor a uno por franja, citas recurrentes y sincronización con Google Calendar.
- El motor sugiere; la base decide. Restricción en PostgreSQL:
  ```sql
  CREATE EXTENSION IF NOT EXISTS btree_gist;

  ALTER TABLE appointments
    ADD CONSTRAINT no_overlap_professional
    EXCLUDE USING gist (
      professional_id WITH =,
      tstzrange(blocks_from, blocks_to) WITH &&
    )
    WHERE (status NOT IN ('cancelled', 'rescheduled'));

  ALTER TABLE appointments
    ADD CONSTRAINT no_overlap_resource
    EXCLUDE USING gist (
      resource_id WITH =,
      tstzrange(blocks_from, blocks_to) WITH &&
    )
    WHERE (resource_id IS NOT NULL AND status NOT IN ('cancelled', 'rescheduled'));
  ```
- Pruebas exhaustivas: cambios de horario, citas contiguas, buffers y reservas simultáneas.
- Es la pieza más delicada del módulo y la base de la página pública.

**Fase 2: Agenda interna**

- Panel para el staff: calendario, crear, mover y cancelar citas.
- Gestión de servicios, profesionales y horarios.
- Primer piloto interno con datos de prueba.

**Fase 3: Reserva pública y recordatorios**

- Página pública de reserva por negocio.
- Notificaciones desacopladas del canal (correo primero, WhatsApp después) mediante trabajos en segundo plano.
- Confirmación, cancelación y reprogramación por el cliente.

**Fase 4: Pilotos reales**

- Entre 2 y 3 negocios reales (un salón, una clínica pequeña) como pilotos gratuitos.
- Recolectar retroalimentación semanal y medir uso diario y reducción de ausencias.

**Fase 5: Producto vendible**

- Suscripción mensual facturada a la organización por sucursales activas, con un plan base económico.
- Despliegue en producción, respaldos, monitoreo y soporte básico.
- Campos específicos por vertical (por ejemplo, fichas de clientes en salones).

**Fase 6: Segundo módulo**

- Elegir el siguiente módulo según lo que pidan los pilotos (depósitos y pagos, paquetes de sesiones, lealtad o facturación).
- Conectarlo a citas mediante eventos.
- No iniciar el segundo módulo hasta cerrar la Fase 4 con pilotos usando el sistema a diario.

## 7. Testing y operación

- Motor de disponibilidad: pruebas property-based sobre invariantes (nunca dos citas solapadas por profesional **ni por recurso**, todo hueco devuelto cae dentro del horario del profesional, el cambio de horario de verano no rompe rangos).
- Autorización: matriz de casos rol × alcance × recurso en specs de Pundit; nada de probar solo el caso feliz.
- Aislamiento de tenant: un spec que itera todos los modelos multi-tenant y verifica que sin tenant no se ven registros, y que un usuario de la empresa A no puede leer datos de la empresa B.
- Observabilidad: Sentry, logs estructurados con request_id, organization_id, company_id y branch_id; endpoints /health y /ready.
- Respaldos: respaldo diario de PostgreSQL y un simulacro de restauración al trimestre. Un respaldo que nunca se restauró no es un respaldo.
- Jobs: cada job recibe `organization_id` (el tenant) y se envuelve en `ActsAsTenant.with_tenant`. Nunca leer `Current` dentro de un job. Encolar después del commit (patrón outbox) para no perder eventos si la transacción falla.
- Privacidad: LFPDPPP en México: aviso de privacidad, consentimiento explícito para recordatorios y derecho de eliminación. Los datos de salud no viven en el módulo de citas.
- Anti-abuso: slugs reservados, rate limiting en la reserva pública y el login, y token firmado (no adivinable) para cancelar o reprogramar desde el correo.

## 8. Riesgos y cómo mitigarlos

- Zonas horarias: guardar todo en UTC y convertir por sucursal. Probar cambios de horario de verano aunque el primer mercado no los use.
- Datos de salud en clínicas: mantener el módulo de citas con datos mínimos. El historial clínico será un módulo aparte, con su propia seguridad, cifrado y consentimiento.
- Costo y aprobación de WhatsApp: la API oficial requiere plantillas aprobadas y tiene costo por conversación. Abstraer el canal de notificaciones desde el inicio y usar correo como alternativa.
- Fuga de datos entre organizaciones: pruebas automáticas que verifiquen el aislamiento entre tenants y revisión del tenant actual en cada solicitud y en cada trabajo en segundo plano.
- Sobrediseño y falta de tiempo: terminar un vertical completo antes de generalizar, y no iniciar pagos, inventario ni facturación hasta que las citas se usen a diario.
- Dependencias entre módulos: mantener Packwerk en CI desde el primer día y activar las reglas de privacidad entre módulos cuando el código crezca.

## 9. Modelo de negocio inicial

- Suscripción mensual facturada a la **organización**, con cantidad = sucursales activas de todas sus empresas; plan base económico y planes superiores según funciones.
- Argumento de venta principal: reducir las ausencias con recordatorios automáticos y recibir reservas desde un enlace compartible.
- El precio sigue siendo por sucursal activa, pero **una sola factura consolidada por organización**; los pilotos (Fase 4) son 3 meses gratis a cambio de acuerdo de datos y uso diario.

## 10. Próximos pasos inmediatos

1. Levantar el entorno Docker y crear las aplicaciones Rails y React.
2. Configurar Packwerk y crear los packs core y appointments.
3. Implementar las migraciones y los modelos base (incluyendo companies, company_modules y company_id donde corresponde).
4. Diseñar y probar el motor de disponibilidad.
5. Identificar los 2 o 3 negocios que servirán como pilotos.

> Análisis aún abierto (branding, roles, onboarding, cobro y otras ideas): ver [`plan-ecosistema-modular-pendientes.md`](plan-ecosistema-modular-pendientes.md).
