# Visión

## Nombre: Ceiba

La **ceiba** es el árbol sagrado de Mesoamérica: en la cosmovisión maya une el inframundo, la tierra y el cielo. Es la metáfora de la arquitectura:

| Árbol | Producto |
| --- | --- |
| Raíces | La plataforma: tenancy, acceso, eventos, auditoría, notificaciones |
| Tronco | La organización |
| Ramas | Empresas, sucursales y **módulos** |

Convención de nombres comerciales: **Ceiba** es el ecosistema; cada módulo es "Ceiba <Módulo>": **Ceiba Citas**, Ceiba Lealtad, Ceiba Pagos… Ver [ADR-0030](adr/0030-nombre-del-producto-ceiba.md).

## Qué construimos

Un **ecosistema de módulos de negocio integrados** para pequeñas y medianas empresas de servicios en **Nicaragua**: clínicas dentales, salones de belleza, barberías y consultorios. Lo pueden usar tanto un negocio independiente como un grupo o franquicia con varias marcas y sucursales.

El primer módulo es **citas**. Los siguientes (depósitos y pagos, paquetes de sesiones, lealtad, facturación, inventario, historial clínico) se construyen **sobre la misma plataforma**, sin rehacerla, y se activan por empresa según lo que cada negocio necesite y pague.

## Para quién

| Perfil | Forma en el sistema | Qué necesita |
| --- | --- | --- |
| Barbería independiente | 1 organización · 1 empresa · 1 sucursal | Que sus clientes reserven solos por WhatsApp/Instagram y que no falten a la cita |
| Clínica con dos consultorios | 1 organización · 1 empresa · 2 sucursales | Agenda por profesional y sala; recordatorios; datos mínimos y protegidos |
| Grupo con una clínica y un salón | 1 organización · 2 empresas · N sucursales | Marcas separadas, clientes separados, administración y reportes consolidados |

Para un negocio pequeño, la interfaz **colapsa** los tres niveles en uno solo: no debe notar que existe una jerarquía.

## Propuesta de valor del primer módulo

1. **Menos ausencias** gracias a recordatorios automáticos por WhatsApp y correo.
2. **Reservas 24/7** desde un enlace compartible (`/c/:slug`) en Instagram y WhatsApp, pensado para un móvil con mala conexión.
3. **Agenda del staff** clara, sin dobles reservas, ni de personas ni de recursos (sillas, salas).

## Mercado: Nicaragua

| Aspecto | Implicación |
| --- | --- |
| Normativa de datos | **Ley 787** de Protección de Datos Personales y su reglamento (Decreto 36-2012): consentimiento por finalidad, prueba del consentimiento, revocación en cualquier momento. Ver [13-privacy-ley-787](architecture/13-privacy-ley-787.md) |
| Zona horaria | `America/Managua` (UTC−6, sin horario de verano). Igualmente se guarda todo en UTC y se prueba el DST, porque el sistema no debe asumir un país |
| Moneda | Córdoba (**NIO**) y dólar (**USD**) conviven en la práctica comercial: la moneda se define **por empresa** |
| Teléfonos | Formato E.164 (`+505…`); el teléfono es el identificador práctico del cliente |
| Canal | **WhatsApp** es el canal dominante; el correo es secundario y sirve de respaldo |
| Cobro de la suscripción | Pasarelas disponibles para comercios locales **por investigar** antes de F6; plan B: cobro manual registrado en el sistema |

## Principios del producto

1. **Simple de operar antes que completo.** Un solo despliegue, pocos servicios y tareas operativas automatizadas. El proyecto se construye en tiempo libre (8–15 h/semana).
2. **Validar con negocios reales antes de generalizar.** No se empieza un segundo módulo hasta que el primero se use a diario en pilotos.
3. **Los cimientos no se negocian.** Aislamiento entre clientes, integridad de la agenda y privacidad se garantizan en la base de datos y en tests automáticos, no solo con disciplina.
4. **Mobile-first para el cliente final; productividad para el staff.**
5. **Extender sin modificar.** Un módulo nuevo se agrega declarándolo ([playbook](playbooks/add-a-module.md)), no tocando la plataforma.

## Principios de arquitectura

| Principio | Cómo se materializa |
| --- | --- |
| Monolito modular | Rails con packs aislados por Packwerk: un despliegue y límites verificados en CI ([02](architecture/02-modular-monolith.md)) |
| Multi-tenant con defensa en profundidad | Tenant = organización; `acts_as_tenant` + FKs compuestas + RLS ([03](architecture/03-multi-tenancy.md)) |
| Deny by default | Toda ruta autenticada y autorizada por permisos declarados ([04](architecture/04-access-control.md), [11](architecture/11-security.md)) |
| Módulos como contrato | Manifiesto por módulo: permisos, settings, eventos, navegación ([05](architecture/05-module-system.md)) |
| Integración por eventos | Outbox transaccional; los módulos no se importan entre sí ([06](architecture/06-events-and-jobs.md)) |
| API-first | Contrato OpenAPI y cliente TypeScript generado ([07](architecture/07-api-contract.md)) |
| La base de datos decide | Las invariantes críticas son restricciones de PostgreSQL, no solo validaciones ([09](architecture/09-data-conventions.md)) |

## Qué NO es (por ahora)

- No es un ERP ni un sistema de historial clínico (este último será un módulo aparte, con su propia seguridad).
- No es una app móvil nativa (la reserva pública es web mobile-first; la PWA o la app quedan para más adelante).
- No hay auto-registro público en el MVP: el alta es asistida ([playbook](playbooks/onboard-an-organization.md)).
- No hay microservicios, Kubernetes ni multi-región.

## Modelo de negocio inicial

- Suscripción mensual **facturada a la organización**, con cantidad = **sucursales activas** de todas sus empresas.
- Prorrateo al dar de alta; las bajas se recalculan en el ciclo siguiente.
- Piloto: **3 meses gratis** a cambio de un acuerdo de datos y uso diario.
- Planes superiores definidos por **entitlements** (qué módulos y límites incluye cada plan) ([05](architecture/05-module-system.md)).
