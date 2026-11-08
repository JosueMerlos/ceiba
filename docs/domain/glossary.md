# Glosario

> Vocabulario ubicuo. El código usa el término en inglés; la conversación y la UI, el término en español.

| Español | Código | Definición |
| --- | --- | --- |
| Organización | `Organization` | Cliente de la plataforma (una marca, grupo o franquicia). **Es el tenant.** Firma el contrato y paga |
| Empresa / negocio | `Company` | Unidad de negocio con giro, marca, moneda, catálogo, profesionales y clientes propios. Activa módulos |
| Sucursal | `Branch` | Ubicación física de una empresa. Define la zona horaria, los horarios de atención y los recursos |
| Giro | `business_type` | Tipo de negocio (salón, dental…). Es configuración, **no** un módulo |
| Módulo | `module_key` | Funcionalidad de negocio activable por empresa (`appointments`, …), descrita por un manifiesto |
| Capacidad de plataforma | pack `platform/*` | Funcionalidad compartida y siempre presente (clientes, notificaciones, auditoría…) |
| Manifiesto | `manifest.rb` | Declaración de un módulo: permisos, settings, eventos, navegación, dependencias |
| Entitlement | `plan_entitlements` | Lo que el plan contratado **permite** (módulos, límites) |
| Activación | `company_modules` | Si un módulo está **encendido** para una empresa |
| Feature flag | Flipper | Liberación gradual de una funcionalidad nueva por organización |
| Persona / usuario | `User` | Ser humano con credenciales; global, puede pertenecer a varias organizaciones |
| Membresía | `Membership` | Vínculo usuario ↔ rol ↔ alcance (organización, empresa o sucursal) |
| Rol | `Role` | Conjunto de permisos con un nivel de alcance (`org_owner`, `receptionist`…) |
| Permiso | `permission_key` | Acción concreta autorizable: `<modulo>.<recurso>.<accion>` |
| Principal | `Access::Principal` | Quien actúa en una request o job: usuario, API key, token público, sistema u operador |
| Operador de plataforma | `PlatformStaff` | Empleado de la plataforma (no de un tenant): da de alta organizaciones y da soporte |
| Contexto | `Current.context` | Organización, empresa, sucursal y principal de la request o job actual |
| Profesional | `Appointments::Professional` | Registro, **por empresa**, de quien presta servicios; tiene horario y citas. Puede vincularse a una persona |
| Recurso | `Appointments::Resource` | Elemento físico reservable (silla, sala, equipo) de una sucursal |
| Servicio | `Appointments::Service` | Prestación del catálogo de la empresa: duración, buffers, precio |
| Buffer | `buffer_before/after_minutes` | Tiempo de preparación o limpieza que bloquea agenda pero no es atención |
| Cita | `Appointments::Appointment` | Reserva de uno o más servicios para un cliente, con un profesional (y opcionalmente un recurso), en una sucursal |
| Intervalo efectivo | `blocks_from` / `blocks_to` | Rango que la cita bloquea en la agenda (servicios + buffers), congelado al reservar |
| Hueco / slot | — | Inicio posible para una cita, calculado por el motor de disponibilidad |
| Ausencia | `Appointments::TimeOff` | Bloque en que un profesional o recurso no está disponible (vacaciones, permiso, almuerzo extendido) |
| Cliente | `Customers::Customer` | Persona que recibe el servicio; único **por empresa**; no entra al panel |
| Consentimiento | `Notifications::Consent` | Autorización del cliente para una **finalidad** y canal (Ley 787) |
| Origen de la cita | `source` | `staff`, `public_booking`, `whatsapp`, `api` |
| Enlace firmado | `PublicToken` | URL de un uso para que el cliente gestione su cita |
| Evento de dominio | `outbox_events` | Hecho ocurrido (`appointment_booked.v1`) que otros módulos pueden escuchar |
| Provisión | `Tenancy::ProvisionOrganization` | Alta de una organización con su primera empresa y sucursal |
