> **HISTÓRICO, no es fuente de verdad.** Desde el 2026-11-07, la documentación vigente vive en [`../docs/`](../docs/README.md). Este archivo se conserva como registro de cómo se llegó a las decisiones; su contenido válido se migró a `docs/` y sus inconsistencias se corrigieron allí (ver `docs/README.md` § Correcciones).

# Plan del ecosistema modular: módulo de citas

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

**Multi-tenancy:** una sola base de datos con identificador de organización en cada tabla (gema acts\_as\_tenant), con políticas de acceso por rol (Pundit). Opcionalmente se agrega Row Level Security en PostgreSQL como segunda capa. Si un cliente grande lo requiere, se puede migrar a una base separada más adelante.

**Jerarquía organizacional:** Organización (marca o franquicia) → Sucursal → Profesionales y recursos. Un negocio pequeño es una organización con una sola sucursal; una franquicia tiene muchas. Los roles (dueño, administrador, staff) pueden aplicar a toda la organización o a una sucursal específica.

**Autenticación:** sesión por cookie httpOnly entre el frontend y la API. Se evita guardar tokens en el navegador, salvo que una app móvil futura lo requiera.

## 4. Modelo de datos (visión general)

**Módulo core**

- Organizaciones, sucursales (con su zona horaria), usuarios, membresías (rol por organización o sucursal) y clientes.
- El cliente es único por organización y lo reutilizarán todos los módulos futuros.

**Módulo appointments**

- Servicios: duración, tiempo de preparación o limpieza (buffer) y precio.
- Profesionales y recursos: una silla o sala se reserva igual que una persona.
- Horarios semanales, ausencias y días libres.
- Citas, con estado (agendada, confirmada, completada, cancelada, no asistió) y origen (staff, página pública, WhatsApp).

**Reglas críticas**

- Todas las fechas se guardan en UTC y se muestran según la zona horaria de la sucursal, no la del navegador.
- La doble reserva se impide en la base de datos mediante una restricción de exclusión sobre el rango de tiempo de cada profesional (incluyendo el buffer). No se confía solo en validaciones del frontend.
- Toda cita se crea por un único punto de entrada, que traduce el conflicto en un error claro (horario ya no disponible).

## 5. Alcance del MVP

Incluido:

- Catálogo de servicios.
- Profesionales con horarios, descansos y días libres.
- Agenda con vista de calendario para el staff.
- Página pública de reservas por negocio, con enlace compartible para Instagram y WhatsApp.
- Recordatorios automáticos por correo y WhatsApp.
- Cancelación y reprogramación por parte del cliente.
- Registro de ausencias.

Excluido por ahora: pagos, facturación, inventario, historial clínico, sincronización con calendarios externos.

## 6. Hoja de ruta por fases

**Fase 0: Fundaciones**

- Entorno Docker funcionando y apps Rails y React creadas.
- Packwerk configurado, con su verificación en CI.
- Packs core y appointments con sus migraciones.
- Autenticación, tenant actual por solicitud y pruebas básicas.

**Fase 1: Motor de disponibilidad**

- Cálculo de huecos libres a partir de horarios, ausencias y citas existentes, en la zona horaria de la sucursal.
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

- Suscripción mensual por sucursal, con un plan base económico.
- Despliegue en producción, respaldos, monitoreo y soporte básico.
- Campos específicos por vertical (por ejemplo, fichas de clientes en salones).

**Fase 6: Segundo módulo**

- Elegir el siguiente módulo según lo que pidan los pilotos (depósitos y pagos, paquetes de sesiones, lealtad o facturación).
- Conectarlo a citas mediante eventos.

## 7. Riesgos y cómo mitigarlos

- **Zonas horarias:** guardar todo en UTC y convertir por sucursal. Probar cambios de horario de verano aunque el primer mercado no los use.
- **Datos de salud en clínicas:** mantener el módulo de citas con datos mínimos. El historial clínico será un módulo aparte, con su propia seguridad, cifrado y consentimiento.
- **Costo y aprobación de WhatsApp:** la API oficial requiere plantillas aprobadas y tiene costo por conversación. Abstraer el canal de notificaciones desde el inicio y usar correo como alternativa.
- **Fuga de datos entre organizaciones:** pruebas automáticas que verifiquen el aislamiento entre tenants y revisión del tenant actual en cada solicitud y en cada trabajo en segundo plano.
- **Sobrediseño y falta de tiempo:** terminar un vertical completo antes de generalizar, y no iniciar pagos, inventario ni facturación hasta que las citas se usen a diario.
- **Dependencias entre módulos:** mantener Packwerk en CI desde el primer día y activar las reglas de privacidad entre módulos cuando el código crezca.

## 8. Modelo de negocio inicial

- Suscripción mensual por sucursal, con un plan base económico y planes superiores según funciones.
- Argumento de venta principal: reducir las ausencias con recordatorios automáticos y recibir reservas desde un enlace compartible.
- Para franquicias: precio por sucursal con visión consolidada de la organización.

## 9. Próximos pasos inmediatos

1. Levantar el entorno Docker y crear las aplicaciones Rails y React.
2. Configurar Packwerk y crear los packs core y appointments.
3. Implementar las migraciones y los modelos base.
4. Diseñar y probar el motor de disponibilidad.
5. Identificar los 2 o 3 negocios que servirán como pilotos.
