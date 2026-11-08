> **HISTÓRICO, no es fuente de verdad.** Desde el 2026-11-07, la documentación vigente vive en [`../docs/`](../docs/README.md). Este archivo se conserva como registro de cómo se llegó a las decisiones; su contenido válido se migró a `docs/` y sus inconsistencias se corrigieron allí (ver `docs/README.md` § Correcciones).

# Pendientes y análisis abierto: ecosistema modular

> Documento de trabajo complementario a `plan-ecosistema-modular-modulo-citas.md`.
> **No forma parte del plan cerrado.** Es el espacio donde vive el análisis que todavía no se decide.
> Estado: **todas las decisiones cerradas (11/11)** · diseño por pulir y backlog restante · 7 de noviembre de 2026

---

## 0. Qué contiene y qué no

Este documento recoge lo que la validación del plan dejó identificado pero **fuera de alcance** de las correcciones técnicas ya aplicadas:

- Lo que el usuario pidió explícitamente y quedó flojo (branding, roles).
- Los vacíos frente al pedido original que aún no se resuelven.
- Las ideas adicionales del brainstorm, priorizadas.
- Un registro de las decisiones ya tomadas, para no reabrirlas por accidente.

**No repite** el plan principal. Si algo ya está cerrado allí, aquí solo se referencia.

---

## 1. Branding por empresa (requisito explícito, sin definir)

El plan menciona "colores, logos, banners" tres veces y no define nada operativo. Es una de las dos peticiones originales con menos desarrollo.

### 1.1 Alcance

El branding vive en la **empresa**, no en la organización ni en la sucursal. Una organización con una clínica y un salón tiene dos identidades visuales distintas.

Elementos mínimos:

- Nombre comercial y lema.
- Colores: primario, secundario, de acento.
- Logo.
- Banner (para la página pública).
- Favicon (opcional).

### 1.2 Modelo de datos

Opción A — columnas y adjuntos en `companies`:

```
companies
  brand_name       string
  tagline          string
  primary_color    string  # hex validado
  secondary_color  string
  accent_color     string
  logo             has_one_attached
  banner           has_one_attached
  favicon          has_one_attached
```

Opción B — tabla `company_brandings` separada.

| | A: columnas en `companies` | B: tabla aparte |
| --- | --- | --- |
| Simplicidad | Alta | Media |
| Historial de cambios de marca | No (salvo `audit_events`) | Sí, si se versiona |
| Peso de la tabla de empresas | Bajo | Nulo |
| Cuándo conviene | MVP | Si el branding se vuelve un producto en sí |

**Recomendación:** A para el MVP. `audit_events` ya guarda el antes/después.

### 1.3 Assets

- Almacenamiento: ActiveStorage. Disco local en desarrollo, S3-compatible en producción (R2 o S3).
- Límites: logo ≤ 2 MB, banner ≤ 5 MB, favicon ≤ 200 KB.
- Formatos aceptados: PNG, JPG, WebP. **SVG solo con sanitización explícita** (riesgo de XSS).
- Variantes generadas con Vips: logo en 1x y 2x, banner recortado a 16:9 y 4:3.
- Las URLs deben ser versionadas o con ETag para invalidar caché al cambiar un asset.

### 1.4 Tema y accesibilidad

- Exponer el branding como variables CSS (`--brand-primary`, `--brand-accent`, …) inyectadas por empresa.
- **Validar contraste.** Una empresa puede elegir un color ilegible. Si el color primario se usa como fondo de botón, exigir contraste ≥ 4.5:1 con el texto; si no cumple, ajustar automáticamente o caer al color por defecto.
- Fallback obligatorio: si una empresa no configuró nada, se usa la paleta base de la plataforma.
- No permitir tipografías arbitrarias en el MVP: fuentes del sistema o una lista curada de tres.

### 1.5 Branding en correos

- Nombre visible del remitente por empresa + logo en la plantilla.
- **No** dominio propio por empresa en el MVP: requiere SPF, DKIM y DMARC por dominio y es soporte garantizado. Se usa el dominio de la plataforma con el nombre de la empresa como remitente visible.
- CSS de correo es limitado: usar tablas y estilos inline, no variables CSS.

### 1.6 Página pública

- Debe cargar el logo y el banner de la empresa, y respetar su paleta.
- Prioridad **mobile-first**: el enlace llega por Instagram y WhatsApp, se abre en 3G.
- Decisión pendiente: ruta `/c/:slug` en el dominio de la plataforma (recomendado para el MVP) o subdominio/dominio propio (después).

### 1.7 Riesgos

| Riesgo | Mitigación |
| --- | --- |
| Temas ilegibles o de mal gusto | Validación de contraste + paleta curada |
| SVG con JavaScript malicioso | Sanitizar o no aceptar SVG en el MVP |
| Correos que se ven distintos según el cliente | Plantillas con tablas y estilos inline |
| Peso excesivo en móvil | Variantes comprimidas, lazy loading, límites de tamaño |
| Caché sirviendo un logo viejo | URLs versionadas o ETag |

### 1.8 Decisiones cerradas (7 de noviembre de 2026)

| Decisión | Resolución |
| --- | --- |
| Modelo | **Columnas y adjuntos en `companies`** (opción A); `audit_events` registra el historial de cambios |
| Editor | **`company_manager` + `org_admin`**: el negocio independiente edita lo suyo; la franquicia puede imponer identidad corporativa |
| URL pública | **Ruta `/c/:slug`** en el dominio de la plataforma; dominio propio queda como upsell (Fase 5+) |
| Tipografía | **Sin tipografía custom**: colores, logo, banner y favicon configurables; fuentes limitadas a 3 curadas |

---

## 2. Catálogo de roles (sin esto, la matriz de Pundit no existe)

El plan ya define `Role`/`UserRole` con scope, pero no enumera los roles. §7 exige una matriz "rol × alcance × recurso" en specs: sin catálogo, no hay nada que probar.

### 2.1 Roles propuestos

| Rol | Scope | Para qué existe |
| --- | --- | --- |
| `org_owner` | organización | Dueño del contrato: cobro, alta de empresas, transferencia de propiedad |
| `org_admin` | organización | Administración global sin acceso a cobro ni a borrar la organización |
| `company_manager` | empresa | Responsable de un negocio: servicios, profesionales, branding, reportes de su empresa |
| `branch_manager` | sucursal | Responsable de una ubicación: agenda, personal, clientes de esa sucursal |
| `receptionist` | sucursal | Opera la agenda: crea, mueve, cancela, hace check-in |
| `professional` | sucursal o empresa | Ve su agenda, bloquea tiempo, marca completada o no asistió |

`client` **no** es un rol de usuario: es un principal público autenticado con token firmado para cancelar o reprogramar. No inicia sesión en el panel.

### 2.2 Matriz de permisos (borrador, no definitiva)

| Recurso | org_owner | org_admin | company_manager | branch_manager | receptionist | professional |
| --- | --- | --- | --- | --- | --- | --- |
| Organización | ver, editar, cobro | ver, editar | — | — | — | — |
| Empresas | crear, editar | crear, editar | ver la suya | — | — | — |
| Sucursales | crear, editar | crear, editar | crear, editar | ver la suya | — | — |
| Branding | — | — | editar | — | — | — |
| Servicios | — | — | CRUD | ver | ver | ver |
| Profesionales | — | — | CRUD | ver, asignar | ver | ver su perfil |
| Clientes | — | — | ver, editar | ver, editar | ver, editar | ver los de sus citas |
| Citas | ver consolidado | ver consolidado | CRUD | CRUD | CRUD | ver y editar las propias |
| Reportes | consolidado | consolidado | de su empresa | de su sucursal | — | — |
| Usuarios y roles | CRUD | CRUD | invitar staff | invitar staff | — | — |

### 2.3 Reglas de composición

- Un usuario puede tener varios roles en varios alcances (por ejemplo, `org_admin` en la organización y `professional` en una sucursal).
- El permiso efectivo es la **unión** de sus roles, cada uno limitado a su alcance.
- Un rol de organización aplica a todas sus empresas y sucursales; uno de empresa, a todas sus sucursales; uno de sucursal, solo a esa.
- **Deny by default.** Toda acción no concedida explícitamente se rechaza.
- Prohibido `current_user.admin?` en cualquier controlador o vista.
- Los roles son plantillas de datos; los roles personalizados por cliente quedan fuera del MVP.

### 2.4 Decisiones cerradas (7 de noviembre de 2026)

| Decisión | Resolución |
| --- | --- |
| Profesional y sucursal | **Asignación por sucursal** (el horario es local). Además, se **separa Persona (`user`) de Profesional**: el registro profesional vive en una empresa y no cruza empresas; la persona puede ser profesional de varias empresas del grupo con registros separados. Motivo: especialista que trabaja 2 días en 2 sucursales de una empresa y el resto de la semana en otra empresa del grupo. La doble-reserva de la *persona* entre empresas se valida en `Appointments::Book` (la constraint de BD cubre registros, no personas) |
| Precios | `branch_manager` **no edita precios**: el catálogo y la economía son del nivel empresa |
| Alcance del `org_admin` | **Solo conteos** en reportes consolidados; el caso de soporte se resolverá en Fase 5–6 con acceso just-in-time auditable |
| Invitaciones | **Sin doble aprobación**: invita quien ya tenga rol de gestión en el scope de destino (branch_manager → su sucursal; company_manager → su empresa; org_owner → org_admin) |

---

## 3. Vacíos restantes frente al pedido original

### 3.1 Onboarding e invitaciones (V5)

Hoy no existe flujo para crear organización → empresa → sucursal ni para dar acceso al staff. Bloquea la Fase 4 (pilotos reales).

Mínimo viable:

- Registro asistido (no auto-registro público en el MVP).
- Asistente: organización → primera empresa → primera sucursal.
- Invitación por correo con token firmado, expiración de 7 días, reenvío y revocación.
- El invitado define contraseña y acepta el aviso de privacidad.
- Transferencia de propiedad y baja de usuario.
- Decidido (7 de noviembre de 2026): **un usuario sí puede pertenecer a varias organizaciones**; selector de organización al entrar y `Current.context` construido tras esa elección. Es la pieza que habilita el caso Persona/Profesional de §2.4.

### 3.2 Alcance del cobro (V6)

El plan dice "suscripción por sucursal", pero ahora hay organización → empresas → sucursales y el cobro queda ambiguo.

| Opción | Ventaja | Desventaja |
| --- | --- | --- |
| Por sucursal, facturado a la organización | Simple de explicar; escala con el uso | Una empresa con muchas sucursales caras |
| Por empresa | Alinea el precio con el "negocio" | Ignora el tamaño real |
| Por organización con tramos | Predecible para franquicias | Difícil de justificar al inicio |

**Recomendación:** facturar a la **organización**, con cantidad = sucursales activas. Da una sola factura a la franquicia y permite consolidar.

Decidido (7 de noviembre de 2026): facturación a la **organización**, con cantidad = sucursales activas de todas sus empresas. **Prorrateo al alta**; una baja se recalcula al ciclo siguiente, sin reembolsos prorrateo. **Piloto: 3 meses gratis** a cambio de acuerdo de datos y compromiso de uso diario (lo que la Fase 4 espera medir).

---

## 4. Ideas adicionales (priorizadas)

### P1 — antes de los pilotos

- **CSRF.** Cookie `httpOnly` + SPA + API exige token CSRF o `SameSite` + validación de `Origin`. No está en el plan y es una vulnerabilidad real. → **Desarrollo completo en `plan-ecosistema-modular-seguridad.md`**, junto con API keys, Rack::Attack y la decisión contra CanCanCan.
- **2FA** para `org_owner` y `org_admin`.
- **Índices** `(branch_id, starts_at)` y `(professional_id, starts_at)` en `appointments`, más política de archivado.
- **Página pública mobile-first** con presupuesto de rendimiento (JS crítico < 150 KB, imágenes lazy).
- **Importación CSV** de clientes, servicios y profesionales para arrancar pilotos.
- **DoD por fase**, no solo Fase 0.
- **WhatsApp:** la aprobación de plantillas de Meta tarda semanas; iniciar el trámite en Fase 0/1, no en Fase 3.

### P2 — durante los pilotos

- **Lista de espera:** al liberarse un hueco, notificar. Alto valor en salones, bajo costo.
- **Duración variable** por servicio (rango mínimo–máximo).
- **Métricas de producto:** % no-show antes/después, % reservas públicas vs staff, tiempo de alta de cita.
- **Zona horaria de reportes consolidados** cuando las sucursales están en husos distintos.
- **Consentimiento de menores** y definición de quién es "responsable" del dato (plataforma o empresa) para LFPDPPP.

### P3 — después

- Dominio propio por empresa.
- Tipografía configurable.
- Roles personalizados por cliente.
- App móvil o PWA.
- Multi-idioma.
- Offboarding formal: exportación, retención y borrado.

### Descartado por ahora

Pagos, facturación, inventario, historial clínico, sincronización con calendarios externos, Kubernetes, microservicios, RLS y particionado de tablas.

---

## 5. Decisiones cerradas (11 de 11, 7 de noviembre de 2026)

| # | Tema | Resolución |
| --- | --- | --- |
| 1 | Branding: modelo | Columnas y adjuntos en `companies` |
| 2 | Branding: editor | `company_manager` + `org_admin` |
| 3 | URL pública | `/c/:slug` en el dominio de la plataforma |
| 4 | Tipografía | No configurable; 3 fuentes curadas |
| 5 | Profesional | Asignación por **sucursal**; **Persona (`user`) separada del Profesional**: la persona puede servir en varias empresas del grupo, el registro profesional no cruza empresas |
| 6 | Precios | `branch_manager` no edita precios |
| 7 | `org_admin` | Solo conteos; soporte con acceso just-in-time auditable en Fase 5–6 |
| 8 | Invitaciones | Aprueba quien tenga rol de gestión en el scope destino |
| 9 | Multi-organización | Un usuario pertenece a varias organizaciones (selector de contexto) |
| 10 | Facturación | A la **organización**, cantidad = sucursales activas de todas sus empresas |
| 11 | Piloto/prorrateo | Prorrateo al alta; baja recalculada al ciclo siguiente; piloto 3 meses con acuerdo de datos |

No quedan decisiones de este documento pendientes. Lo que queda aquí es **diseño por pulir** (§1.2–§1.6, §2.2) y **backlog priorizado** (§4).

---

## 6. Decisiones ya aplicadas (no reabrir sin motivo)

Registro de lo cerrado, para que una sesión futura no lo deshaga por desconocimiento.

| Decisión | Motivo |
| --- | --- |
| Jerarquía Organización → Empresa → Sucursal | Sin el nivel Empresa, la clínica y el salón del mismo grupo mezclan datos |
| Cliente único por **empresa** | Privacidad y giros distintos |
| Tenant de `acts_as_tenant` = organización | Frontera dura; empresa y sucursal son alcances de autorización |
| `company_modules(company_id, module_key, …)` | Permite módulos distintos por empresa sin condicionales sobre el giro |
| El giro NO es un módulo | Clínica y salón comparten el pack `appointments`; evita duplicar el motor |
| Citas con `appointment_services` | "Corte + tinte" es una cita, no dos |
| Buffer como `blocks_from`/`blocks_to` | Snapshot inmutable; editar un servicio no altera el historial |
| Constraints separadas para profesional y recurso | Una silla también puede doble-reservarse |
| Reprogramación con `FOR UPDATE` + `WHERE status = 'scheduled'` | Evita dos citas nuevas en concurrencia |
| RBAC como datos con scope | Evita `current_user.admin?` disperso |
| `audit_events` append-only + `idempotency_key` | Trazabilidad y reintentos seguros |
| Un único punto de entrada `Appointments::Book` | Coherencia de conflictos y respuestas `409` |

---

## 7. Referencias

- `plan-ecosistema-modular-modulo-citas.md` — plan cerrado (232 líneas).
- `plan-ecosistema-modular-modulo-citas-bk.md` — original respaldado (131 líneas, sin cambios).
- `plan-ecosistema-modular-seguridad.md` — diseño de seguridad API-first (credenciales, Rack::Attack, autorización).
