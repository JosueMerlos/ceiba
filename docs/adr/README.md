# Registro de decisiones de arquitectura (ADR)

Cada decisión relevante tiene su ADR ([plantilla](../templates/adr.md)). Un ADR aceptado **no se edita** para cambiarlo: se crea otro que lo reemplaza y se marca el anterior como `reemplazada por ADR-xxxx`.

| # | Decisión | Estado |
| --- | --- | --- |
| [0001](0001-monolito-modular-packwerk.md) | Monolito modular con Packwerk y capas | aceptada |
| [0002](0002-postgresql-18.md) | PostgreSQL 18 como motor (frente a MySQL) | aceptada |
| [0003](0003-tenant-es-la-organizacion.md) | El tenant es la organización | aceptada |
| [0004](0004-jerarquia-organizacion-empresa-sucursal.md) | Jerarquía Organización → Empresa → Sucursal | aceptada |
| [0005](0005-rls-preparado-activado-en-piloto.md) | RLS preparado desde el día 0, activado antes de los pilotos | aceptada |
| [0006](0006-uuidv7-como-clave-primaria.md) | UUIDv7 como clave primaria | aceptada |
| [0007](0007-pundit-sobre-cancancan.md) | Pundit (no CanCanCan) | aceptada |
| [0008](0008-permisos-como-datos.md) | Permisos como datos, declarados por los módulos | aceptada |
| [0009](0009-sidekiq-con-outbox.md) | Sidekiq + Redis con outbox transaccional | aceptada |
| [0010](0010-modulos-por-empresa-y-manifiesto.md) | Módulos por empresa y descritos por un manifiesto | aceptada |
| [0011](0011-el-giro-no-es-un-modulo.md) | El giro no es un módulo | aceptada |
| [0012](0012-contrato-openapi-y-cliente-generado.md) | Contrato OpenAPI y cliente TS generado | aceptada |
| [0013](0013-monorepo-y-mismo-origen.md) | Monorepo y un solo origen | aceptada |
| [0014](0014-calendario-gratuito-con-adaptador.md) | Agenda con librería gratuita detrás de `AgendaView` | aceptada |
| [0015](0015-reserva-publica-app-separada.md) | Reserva pública como app React separada | aceptada |
| [0016](0016-credenciales-por-superficie.md) | Credenciales por superficie; sin JWT hasta la app móvil | aceptada |
| [0017](0017-sesiones-en-bd-sin-devise.md) | Sesiones en BD, autenticación propia sin Devise | aceptada |
| [0018](0018-integridad-de-agenda-en-bd.md) | Integridad de agenda en la BD y un único punto de entrada | aceptada |
| [0019](0019-reprogramar-crea-cita-nueva.md) | Reprogramar crea una cita nueva | aceptada |
| [0020](0020-persona-separada-de-profesional.md) | Persona separada del profesional | aceptada |
| [0021](0021-cliente-unico-por-empresa.md) | Cliente único por empresa, en `platform/customers` | aceptada |
| [0022](0022-auditoria-append-only-e-idempotencia.md) | Auditoría append-only e idempotencia | aceptada |
| [0023](0023-notificaciones-como-plataforma.md) | Notificaciones como capacidad de plataforma | aceptada |
| [0024](0024-mercado-nicaragua.md) | Mercado inicial: solo Nicaragua | aceptada |
| [0025](0025-branding-en-companies.md) | Branding en `companies` | aceptada |
| [0026](0026-facturacion-a-la-organizacion.md) | Facturación a la organización por sucursal activa | aceptada |
| [0027](0027-rate-limiting-en-dos-capas.md) | Rate limiting en dos capas | aceptada |
| [0028](0028-usuario-multi-organizacion.md) | Usuario en varias organizaciones | aceptada |
| [0029](0029-citas-multi-servicio.md) | Citas con varios servicios y precios congelados | aceptada |
| [0030](0030-nombre-del-producto-ceiba.md) | El producto se llama Ceiba | aceptada |
| [0031](0031-tokens-de-diseno-en-tres-capas.md) | Tokens de diseño en tres capas con los nombres semánticos de shadcn/ui | aceptada |
| [0032](0032-lenguaje-visual-marco-y-hoja.md) | Lenguaje visual: marco suave con hoja blanca en el panel, reserva toda blanca | aceptada |
