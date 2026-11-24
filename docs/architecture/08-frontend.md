# 08 — Frontend

> Decisiones: [ADR-0013](../adr/0013-monorepo-y-mismo-origen.md), [ADR-0014](../adr/0014-calendario-gratuito-con-adaptador.md), [ADR-0015](../adr/0015-reserva-publica-app-separada.md), [ADR-0025](../adr/0025-branding-en-companies.md). Hitos: M0.01, M0.12, M2.02, M2.04, M3.02.

## Workspace

```
frontend/                      pnpm workspace
  apps/
    panel/                     SPA del staff (escritorio y tablet primero)
    booking/                   reserva pública (móvil primero, 3G)
  packages/
    ui/                        design system: primitivas (shadcn/ui), tokens, componentes compuestos
    api-client/                cliente generado desde OpenAPI (M0.06: openapi-fetch, ApiError, unwrap) + CSRF automático y hooks de TanStack Query (M0.12)
    branding/                  tema por empresa: CSS vars, validación de contraste, fallback (M2.04; aún no existe)
    i18n/                      configuración de i18next y catálogo es-NI (M0.12)
    config/                    tsconfig, eslint, prettier y vitest compartidos + medición del presupuesto de bundle
  e2e/                         Playwright sobre Docker Compose (M0.12)
```

Las dependencias entre paquetes son explícitas en cada `package.json`. Una app nunca importa archivos de otra app.

## Stack

| Necesidad | Elección | Nota |
| --- | --- | --- |
| Build | Vite | — |
| Lenguaje | TypeScript `strict` | Sin `any` implícito |
| Router | **React Router 8.5.1 (modo data)** | Decidido en M0.12 con una prueba corta ([ver abajo](#router-decisión-de-m012)) |
| Estado del servidor | TanStack Query | El estado de la API **no** se copia a stores globales |
| Estado de UI | Estado local + contexto; Zustand solo si se justifica | — |
| Formularios | react-hook-form + zod | Esquemas zod alineados con los errores `422` de la API |
| Estilos | Tailwind + shadcn/ui | Componentes copiados al repo (`packages/ui`), no una dependencia opaca |
| Fechas | `date-fns` + `@date-fns/tz` | Siempre con la zona de la **sucursal**, nunca la del navegador. Un solo formato en el panel: «9:00 a. m.» y «lun 14 dic 2026» ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md)) |
| Selectores de fecha y hora | `react-day-picker` (el `Calendar` de shadcn/ui, carga diferida) para la fecha; `TimeField` y `DurationField` propios sobre Radix `Popover` | Sin inputs nativos de fecha u hora ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md), desde M2.05) |
| Agenda | `AgendaView` propio sobre `@event-calendar/core` 5.19.0 (MIT, elegida en M2.02) | Ver abajo |
| i18n | react-i18next, locale `es-NI` | Todos los textos se extraen desde el día 1 |
| Tests | Vitest + Testing Library + MSW; Playwright para E2E | [12](12-testing-strategy.md) |

## Panel: arquitectura

```
apps/panel/src/
  app/                 bootstrap, providers, router raíz, layout
  platform/            auth, selector de contexto, sesión, /me, gates de permiso, errores
  modules/
    appointments/
      index.ts         manifiesto del front: rutas lazy, navegación, permisos requeridos
      routes/          páginas (contenedores)
      components/      presentacionales del módulo
      api/             hooks específicos (sobre packages/api-client)
  shared/              utilidades sin dominio
```

- **Container/presentational:** las páginas (`routes/`) obtienen datos y manejan efectos; los componentes reciben props y son puros y testeables.
- **Registro de módulos:** `modules/registry.ts` importa estáticamente los `index.ts` de cada módulo. Al arrancar, `/api/v1/me` dice cuáles están activos y qué permisos hay. El router monta **solo** las rutas de los módulos activos (lazy, un chunk por módulo) y la navegación se filtra por permiso.
- **Gates:** `<Can permission="appointments.appointment.create">` y `useCan()` solo **reflejan**; el backend es el que decide.
- **Selector de contexto:** organización → empresa → sucursal. Si el usuario solo tiene uno de cada nivel, el selector no se muestra. Cambiar de contexto invalida la caché de TanStack Query.
- **Errores:** `@ceiba/api-client` ya entrega el error tipado (`ApiError { status, code, errors, requestId }`, M0.06; ver [07](07-api-contract.md#generación-del-contrato-y-del-cliente-typescript)). Un `ApiError` con `code` se traduce por i18n; un `401` lleva al login; un `403` muestra una pantalla de permiso; un `409` en la agenda refresca y avisa "el horario ya no está disponible".

## Implementación (M0.12)

Versiones fijadas: React Router 8.5.1, TanStack Query 5.107.1, Tailwind 4.3.5, `radix-ui` 1.8.1 (paquete unificado de Radix), i18next 27.1.0 + react-i18next 18.0.1, react-hook-form 7.91.0 (con su validación nativa; zod + `@hookform/resolvers` se añaden cuando haya esquemas compartidos con los `422`, no antes: pesaban en el arranque), sonner 2.0.8 (el "toast" de shadcn/ui), lucide-react 1.70.0, MSW 3.0.4 y Playwright 1.65.0. TypeScript 7.0.2 en apps y en `ui`/`i18n`/`e2e`; 6.0.3 solo donde ya estaba (`config`, `api-client`; ver [07](07-api-contract.md)).

### Router: decisión de M0.12

Prueba de ~15 min (build de Vite con una ruta lazy y un loader en cada router): ambos parten el módulo en un chunk aparte y pesan lo mismo (React Router 99.7 KB gzip, TanStack Router 95.4 KB). Se eligió **React Router en modo data** porque el criterio que pesa aquí es **montar rutas a partir de `/api/v1/me` en tiempo de ejecución** (los módulos activos dependen de la empresa), y eso encaja con `useRoutes` sobre una lista que se calcula con los datos del contexto; el árbol de TanStack Router es estático y su tipado fuerte de rutas se pierde justo en esa parte dinámica. Los loaders tipados no se necesitan: los datos viven en TanStack Query. No hay ADR (el hito lo pide solo si se elige TanStack Router). Se revisa si el panel gana rutas estáticas con muchos parámetros de búsqueda tipados (agenda, F2).

### Estructura del panel

```
apps/panel/src/
  main.tsx, styles.css          arranque (Sentry de M0.13, createApp, estilos)
  app/
    create-app.ts               compone i18n, cliente de la API (con su CsrfStore), QueryClient y router; un panel por llamada (testeable)
    app.tsx                     providers: i18n, QueryClient, ApiClient, RouterProvider, Toaster
    router.tsx                  /login y la zona privada: RequireSession -> Workspace -> (inicio | ModuleRoutes)
  platform/
    auth/                       login-page, require-session, return-path (ruta de retorno sin open redirect)
    me/ , permissions/          MeProvider/useMe y <Can>/useCan
    context/                    ContextProvider (qué se le pide a /me), ContextSelector (contenedor) y ContextMenu (presentacional)
    errors/                     global-errors (política de errores) y status-pages (403, 404, inesperado, RouteError)
    shell/                      AppShell (layout), UserMenu, HomePage, Workspace (carga /me) y ModuleRoutes
  modules/
    registry.ts, types.ts, lazy-page.tsx
    appointments/index.tsx      manifiesto del front (rutas y navegación con sus permisos)
    appointments/routes.tsx     páginas placeholder (el chunk del módulo)
  test/                         MSW, fixtures de /me y renderApp (el panel completo contra una API simulada)
```

### Registro de módulos

`modules/registry.ts` importa estáticamente solo el **manifiesto** de cada módulo (`index.tsx`); las páginas se cargan con `import()` desde `lazyPage(...)`. Tres funciones puras sobre `/me`: `activeModules(me)` (los activos que este front conoce), `routesFor(me)` (rutas de módulos activos cuyo permiso tiene el usuario) y `navigationFor(me)` (ítems con permiso **y** ofrecidos por `navigation` de `/me`). Una URL de un módulo inactivo, o sin permiso, cae en «no encontrado» (como el 404 que daría el backend). Vite emite cada módulo en `assets/module-<clave>-<hash>.js` (`chunkFileNames` en `vite.config.ts`); `app/build.test.ts` lo verifica con el manifest del build (criterio 6).

### Contexto

`ContextProvider` guarda lo que se le pide a `/me` (vacío = el último contexto usado por la cookie `ceiba_context` o el primero disponible). Cambiar de contexto llama a `queryClient.removeQueries` sobre todo lo que no sea la sesión: se descarta, no se invalida, para que **nunca** se vea un dato de la organización anterior mientras llega el nuevo. El selector pide organizaciones, empresas y sucursales (máx. 100 por nivel, el tope de la API); muestra solo los niveles con más de una opción y se oculta si no hay nada que elegir; las organizaciones suspendidas aparecen deshabilitadas (elegirlas daría 403 en `/me` y dejaría al usuario sin selector).

### Errores (política global, `platform/errors/global-errors.ts`)

| Caso | Qué pasa |
| --- | --- |
| `401` (salvo `auth.invalid_credentials`) en cualquier consulta o mutación | Se descarta toda la caché y se va a `/login?next=<ruta actual>`; tras entrar vuelve ahí. `next` solo admite rutas internas |
| `403` / `404` en una consulta | `throwOnError`: la pantalla de permiso / «no encontrado» (`RouteError`) |
| `409`, `403`, `429`, `5xx` o fallo de red en una **mutación** | Aviso (toast) con el mensaje por `code`; el `409` usa un aviso amarillo ("la información cambió…") |
| `400`/`422` en una mutación | Lo muestra el formulario (`errors[]`); sin aviso global |
| Reintentos | Nunca en `4xx`; hasta 2 en `5xx`/red |

**Modo híbrido de rutas.** El router de datos define las rutas estáticas (`/login`, la zona privada y las páginas de inicio) y las rutas de los módulos activos se resuelven **dentro** de la ruta comodín `*` con `useRoutes` (`ModuleRoutes`), porque dependen de `/me` y no se conocen al crear el router. No se migró a `patchRoutesOnNavigation` porque obligaría a conocer `/me` antes de la primera navegación y a duplicar la lógica de permisos en el router; se revisa si los módulos ganan loaders. Hay **dos límites de error**: el de la zona privada (`RouteError withLogout`: un fallo de la sesión o de `/me` no deja layout y solo cabe salir) y uno **dentro del layout** (un `403`/`404`/error de una página sustituye a la página y deja visibles la navegación y el selector). El selector de contexto va en su propio límite silencioso: si fallan sus listas, desaparece sin tirar la cabecera.

**Convención de datos.** Toda query de negocio vive bajo `MeGate` (dentro de `Workspace`) o lleva el contexto en su `queryKey`. Cambiar de contexto descarta TODA la caché que no sea la sesión; una query con una clave global que se montara fuera de `Workspace` sobreviviría al cambio y mostraría datos de la organización anterior.

El mensaje sale de `errors:code.<code>` (i18n); si el `code` no está traducido, del estado HTTP. Nunca del `message` del servidor.

### packages/ui y tokens

Tailwind 4 + componentes de shadcn/ui copiados al repo, **solo los que usa el hito**: `Button` (con `loading` y `asChild`), `Input`, `Label`, `Form*` (react-hook-form, errores asociados con `aria-describedby` y `role="alert"`), `Dialog`, `DropdownMenu`, `Toaster` (Sonner), más `AppLayout`/`NavItem`/`PageHeader`/`StatusPage`/`LoadingState`/`CeibaMark`. Los textos los recibe el componente por props (el paquete no conoce i18n). Tokens en tres capas con los nombres semánticos de shadcn/ui y `--brand-*` como lo que M2.04 sobrescribe por empresa: ver [ADR-0031](../adr/0031-tokens-de-diseno-en-tres-capas.md) (incluye la trampa de que el branding se escribe en `:root`). Tipografía: Bricolage Grotesque (titulares) y Figtree (cuerpo), autoalojadas con Fontsource (cumplen la CSP `font-src 'self'`). Foco visible, `prefers-reduced-motion` respetado, enlace "Saltar al contenido", navegación con `aria-current="page"` y, bajo `md`, la navegación pasa a una fila deslizable bajo la cabecera.

### Componentes del rediseño v2 (M2.05)

Base de [ADR-0043](../adr/0043-rediseno-v2-del-panel.md) para M2.06–M2.08. Reciben sus textos y sus formatos por props (el paquete sigue sin conocer i18n): la app pasa `formatClock`, `formatPlainDate` y los `t(...)`. En el panel no se repiten en cada uso: `platform/forms/branch-fields.tsx` exporta `BranchDatePicker` (calcula «hoy» con la zona de la sucursal), `BranchTimeField` y `BranchTimeRangeField` con todo eso ya fijado. **Excepción deliberada:** los nombres de mes y de día del calendario salen del locale `es` de `react-day-picker`, que vive dentro del chunk diferido del calendario; pasarlo por props lo metería en el código de la app. Los valores son siempre texto de pared de la sucursal, nunca un `Date` del navegador.

| Componente | API | Notas |
| --- | --- | --- |
| `AppLayout` | sin cambios de props | Alto fijo: el marco es `h-svh overflow-hidden`, la barra lateral no se mueve y `<main>` (`#contenido-principal`) es un bloque con `overflow-y-auto`: cualquier pantalla se desplaza dentro de la hoja sin tocarla. No hay scroll de documento |
| `PageFrame` + `PageBody` | `div` con `className` | Opcional, para encabezado fijo y cuerpo con scroll propio (agenda, tablas largas): `<PageFrame><PageHeader …/><PageBody>…</PageBody></PageFrame>`. `PageBody` es la única región que se desplaza |
| `ContextPanel` | `+ variant: "floating" \| "docked"` (por defecto `floating`) | Flotante: `absolute` sobre el borde derecho de la hoja (el contenedor de la hoja es `relative`), no le quita ancho. `docked`: columna de `w-80` desde `lg` (solo Marca). Sigue no modal, con Escape, foco de vuelta y `aria-expanded`/`aria-controls`. Una pantalla no lo abre por su cuenta: tapa lo que hay debajo (y, abierto, también la barra de scroll de la hoja) |
| `FormDialog` | `open`, `onOpenChange`, `title`, `description?`, `closeLabel`, `children` (el formulario, `id={formId}`) y una de tres formas: **pasos** (`steps: {id,label,optional?}[]`, `step`, `stepsLabel`, `onBack`, `onSkip?`, `formId`, `backLabel`, `skipLabel`, `continueLabel`, `finishLabel`, `pending?`), **pestañas** (`tabs: {id,label}[]`, `tab`, `onTabChange`, `tabsLabel`, `dirty`, `formId`, `saveLabel`, `pending?`, `confirmTitle`, `confirmDescription`, `discardLabel`, `keepLabel`) o **simple** (`footer?`) | Grande (`sm:max-w-3xl`), encabezado y pie fijos, cuerpo con scroll (`data-slot="form-dialog-body"`), foco atrapado (Radix). Continuar/Guardar son `type="submit" form={formId}`: el `onSubmit` de la app valida, guarda y decide avanzar. Con `dirty`, cambiar de pestaña o cerrar (X, Escape, fondo) pide confirmar con `ConfirmDialog`. Un solo botón de guardar visible. Los popovers de los campos (lista de horas, calendario) se montan dentro del modal por `PortalContainerContext`: fuera de él, el bloqueo de scroll del modal congelaría su lista |
| `TimeField` | `value` (`"HH:mm"` o `""`), `onChange`, `onBlur?`, `formatClock`, `listLabel`, `min="00:00"`, `max="23:59"`, `step=15`, `aria-*`, `id`, `name`, `disabled`, `ref` | Combobox de WAI-ARIA sobre Radix `Popover`: ↑/↓ mueven la opción activa, Enter o salir confirman, Escape cierra la lista (sin cerrar el modal). Se escribe «9», «930», «930p», «2:15 p. m.» (`parseClock`, sin sufijo = 24 h); se aceptan minutos fuera del paso. Lo inválido o fuera de rango deja el texto a la vista marcado con `aria-invalid` y emite `""`, para que la validación del formulario bloquee el guardado (nunca queda guardada la hora anterior). Escape cierra la lista y, con la lista cerrada, cancela lo escrito. Un clic en cualquier otro sitio confirma lo escrito antes de que nadie reaccione a ese clic (un modal que decide si pedir confirmación ve `dirty` al día). Si el valor cambia desde fuera (otra hora, un `reset`), lo escrito se descarta |
| `TimeRangeField` | `value: {start,end}`, `onChange`, `startLabel`, `endLabel`, `formatClock`, `listLabel`, `aria-label?`, `fieldClassName?` | Dos `TimeField` en una franja compacta (la usa el editor de horarios); con `aria-label` es un grupo, sin él solo maqueta. No reordena un rango invertido (lo valida el formulario) |
| `DurationField` | `value` (min), `onChange`, `formatDuration`, `decreaseLabel`, `increaseLabel`, `presetsLabel`, `min=5`, `max=480`, `step=5`, `presets=[15,30,45,60,90]` | −/+ deshabilitados en los límites; atajos con `aria-pressed`, solo los que caben en el rango |
| `DatePicker` / `DateRangePicker` | `value` (`"yyyy-MM-dd"` o `""`; rango `{from,to}` con `to: null` mientras falta el fin), `onChange`, `today` (hoy en la zona de la sucursal, `todayInZone`), `formatDate`, `placeholder`, `calendarLabel`, `previousMonthLabel`, `nextMonthLabel`, `loadErrorLabel`, `retryLabel`, `min?`, `max?`, `aria-*`, `id`, `ref` | Disparador liviano + calendario `react-day-picker` 10.0.2 cargado con `lazy` (`calendar.tsx`, nunca exportado por el barrel): semana desde el lunes, hoy con anillo, elegido relleno. Los días viajan como mediodía local, así que ninguna zona del navegador los corre. Rango: primer clic inicio, segundo fin; un clic anterior al inicio lo reemplaza; al completarlo se cierra. Si el chunk no descarga (un despliegue lo reemplazó, sin red), el aviso con «Reintentar» queda dentro del selector y no tumba la pantalla |
| `ConfirmDialog` | `open`, `onOpenChange`, `title`, `description`, `confirmLabel`, `cancelLabel`, `onConfirm` | Radix `AlertDialog` para preguntas que bloquean (descartar cambios) |

**Formato único** ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md)): `@ceiba/i18n` exporta `formatTime(instante, zona)` → «9:00 a. m.», `formatClock("21:30")` → «9:30 p. m.», `formatDate(instante, zona)` y `formatPlainDate("2026-12-14")` → «lun 14 dic 2026», y `formatDateTime` → «lun 14 dic 2026, 9:00 a. m.». Normalizan a espacio duro (U+00A0) los espacios que inserta ICU (U+0020, U+00A0 o U+202F según el motor), así el texto es idéntico en Node y en los navegadores y nunca se parte. `shortClock` y `formatInZone` se retiraron.

**Guardia contra inputs nativos:** la regla `no-restricted-syntax` del config compartido rechaza `type="time"`, `type="date"` y `type="datetime-local"` (también `type={"date"}`) en `apps/*/src` y `packages/ui/src`, en el mismo bloque que las guardas de textos de UI (un segundo bloque con la misma regla las anularía). Probada en `packages/config/test/eslint.test.ts`.

### i18n

`packages/i18n`: instancia **nueva** por `createI18n()` (nada global), catálogo `es-NI` tipado (una clave que no existe no compila) por namespaces (`common`, `auth`, `shell`, `errors`, `appointments`, `booking`) y formatos `Intl` (`formatCurrency` escribe "US$" para el dólar porque CLDR da "USD" en es-NI; `formatDate/Time/DateTime` exigen la zona de la sucursal). **Regla de ESLint** `i18next/no-literal-string` (eslint-plugin-i18next 6.1.5, funciona con ESLint 10) en `apps/*/src/**/*.tsx` y `packages/ui/src/**/*.tsx`, modo `jsx-only`: revisa el texto JSX y los atributos que el usuario lee (`alt`, `title`, `label`, `placeholder`, `aria-label`, `aria-description`…); los tests quedan fuera. Probada en `packages/config/test/eslint.test.ts`.

### CSRF y hooks en `@ceiba/api-client`

`createApiClient` instala un middleware: toda mutación lleva `X-CSRF-Token`; el token se captura del cuerpo de `POST /auth/login` y de `GET /auth/session` (que la SPA llama al arrancar), vive **solo en memoria** (`CsrfStore`) y se olvida al cerrar sesión o ante un `401`. Hooks base: `useSessionQuery`, `useMeQuery(contexto)`, `useOrganizationsQuery`, `useCompaniesQuery`, `useBranchesQuery`, `useLoginMutation` (con `meta.silent`: su error lo muestra el formulario), `useLogoutMutation` y `useLogoutAllMutation` (vacían la caché). `queryKeys` centraliza las claves.

### Presupuesto de bundle y E2E

- `apps/booking`: JS crítico (entrada + imports estáticos) **< 150 KiB gzip**, medido por `frontend/bin/ci-bundle` (etapa `frontend-bundle` de `bin/ci`, job de CI y `src/build.test.ts`). Hoy: **85.3 KiB** (React + i18next + la página base). `packages/config/bundle-budget.mjs` lee el manifest de Vite; los imports dinámicos no cuentan. Subir el umbral exige cambiar el ADR-0015.
- Panel: presupuesto de **220 KiB** gzip de JS crítico (medido **198.5 KiB** + ~10 % de margen al fijarlo; antes de la revisión eran ≈ 225 KiB). Se logró difiriendo Sentry (chunk propio, solo con DSN), quitando zod y el resolver del login (validación nativa de RHF) y cargando perezosamente el diálogo de «cerrar todas las sesiones». Los límites de ambas apps viven en `frontend/bundle-budgets.json` (una sola fuente; `bin/ci-bundle` los comprueba). **Ambos presupuestos miden solo JS** (ni CSS ni fuentes). Booking carga hoy el catálogo i18n completo (unos pocos KiB de texto): se separará por namespace cuando crezca el catálogo.
- **Medición de M2.05 (panel):** 215.8 KiB antes (el crecimiento de M2.01–M2.04 ya había gastado casi toda la holgura de ~21 KiB que suponía ADR-0043) y **216.7 KiB** después (+0.9 KiB: textos de i18n, envoltorios del panel y el aviso de reintento del calendario). `react-day-picker` y su `date-fns` viajan solo en el chunk diferido del calendario (22.5 KiB gzip), lo fija `apps/panel/src/app/build.test.ts`. Quedan **~3.3 KiB**: lo que M2.06–M2.08 sumen al arranque debe ir diferido. Booking: 95.1 KiB.
- **E2E** (`frontend/e2e`, Playwright 1.65.0): el servicio `e2e` de `compose.yaml` (perfil `e2e`, imagen `infra/docker/e2e.Dockerfile` con la misma versión de Playwright, comprobado por `check-versions.sh`) comparte la red del proxy (`network_mode: service:proxy`) y entra por `http://localhost:8080`, igual que un navegador. Corre contra los seeds de demo. `make e2e` o `bin/ci e2e`; en GitHub, el job `e2e` solo en `main` (sube el reporte y las capturas como artefacto). Los tests no escriben datos y cada uno inicia su propia sesión. Funciona con cualquier `PROXY_PORT` (Caddy escucha y publica en el mismo puerto; verificado con 38080) y la imagen no lleva etiqueta fija, así que varios entornos pueden convivir. Dependen de los **límites de Rack::Attack de desarrollo** (1000 logins por IP/15 min, `backend/config/middleware/rate_limiting.rb`): una corrida inicia ≈ 10 sesiones. Sin reintentos por defecto (`E2E_RETRIES`; el job de `main` usa 1). Seeds: `ana@multi-org.ceiba.test` está en dos organizaciones (cambio de organización), `luis@` en dos empresas, `rosa@` y `recepcion@barberia-guegu` en una sola.

## `AgendaView`: calendario detrás de un adaptador

La vista de día por profesionales y recursos es la pantalla más usada. Desde [M2.06](../milestones/F2-agenda-interna/M2.06-agenda-en-filas.md) muestra los profesionales (o recursos) en **filas** y las horas en columnas, con el plugin `ResourceTimeline` y scroll vertical interno; la vista Semana muestra un profesional a la vez y en el celular la agenda es una lista por profesional con el mismo `AgendaViewProps` ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md)). FullCalendar la ofrece solo en su plan **Premium** (licencia comercial), así que se descarta.

```ts
interface AgendaViewProps {
  date: PlainDate; timeZone: string;            // zona de la sucursal
  resources: AgendaResource[];                   // profesionales / sillas / salas
  events: AgendaEvent[];                         // citas y bloqueos
  businessHours: AgendaHours[];
  onSelectSlot(slot): void; onMoveEvent(e, to): void; onOpenEvent(e): void;
}
```

- La página habla **solo** con `AgendaView`; la librería concreta vive en `AgendaView/adapters/<lib>.tsx`.
- Criterios para elegir la librería en M2.02: licencia MIT o similar, vista diaria por recursos, drag & drop, buen manejo de zonas horarias, mantenimiento activo y peso.
- Si ninguna cumple, plan B: una vista diaria por recursos **propia** (grilla CSS), que para una vista de un solo día es razonable.
- **Elegida en M2.02: `@event-calendar/core`** (comparación en las [notas del hito](../milestones/F2-agenda-interna/M2.02-agenda-del-staff.md#notas-de-cierre)). El adaptador la hace correr en UTC y le entrega la hora de pared de la sucursal, así que nada depende de la zona del navegador. Vive en su propio chunk, que la página precarga junto con sus datos.
- Horarios y ausencias se piden cuando el navegador queda libre tras pintar las citas: sombrear lo cerrado no compite con el primer clic.

## Booking (`apps/booking`)

- Ruta: `/c/:slug` (mismo origen, servida por el proxy).
- **Presupuesto:** JS crítico < 150 KB gzip, LCP < 2.5 s en 3G rápido emulado, imágenes lazy con variantes.
- Sin el design system completo: usa los tokens y unas pocas primitivas de `packages/ui`, con tree-shaking.
- Flujo: servicio(s) → profesional (o "cualquiera") → día y hora → datos (nombre y teléfono) → consentimiento → confirmación.
- Lee la configuración pública de la empresa (branding, servicios, `public_booking_enabled`) en una sola llamada cacheable.
- Envía `Idempotency-Key` generado al iniciar la confirmación (un doble tap no duplica la cita).
- CSP estricta ([11](11-security.md)).

## Lenguaje visual (F2 en adelante)

Decidido en [ADR-0032](../adr/0032-lenguaje-visual-marco-y-hoja.md), que reemplaza el layout de M0.12 a partir de F2, y enmendado por [ADR-0043](../adr/0043-rediseno-v2-del-panel.md) (rediseño v2, M2.05–M2.08):

- **Panel:** marco con tinte suave (`--sidebar-*`) y cada pantalla sobre una hoja blanca (`--background`). Sin cabecera superior: logo, selector de contexto, menú y usuario viven en el marco.
- **Barra lateral contraíble** a un riel de íconos, con la preferencia guardada por usuario en `localStorage`. Arranca contraída por debajo de 1280 px.
- **Panel contextual a la derecha, colapsable y no modal, que flota sobre la hoja** sin robarle ancho: "Próximas llegadas" y el detalle de la cita en la agenda, y el detalle rápido de lectura en los catálogos. La pantalla de Marca conserva el panel acoplado (editor con vista previa en vivo). Enmienda de [ADR-0043](../adr/0043-rediseno-v2-del-panel.md) al ítem 4 de ADR-0032.
- **Catálogos en modal central** con pasos (crear) o pestañas (editar) y un solo botón de guardar visible; la recepción los ve en lectura limpia, sin botones de crear ni ayudas de edición ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md)).
- **Alto fijo:** el layout ocupa la ventana; el marco queda estático y cada pantalla desplaza solo su cuerpo (`AppLayout`, `PageFrame`/`PageBody`, desde M2.05).
- **Sucursal solo en el selector global** (sin selector «Sucursal de trabajo» por pantalla).
- **Estados de la cita** distinguibles por luminosidad, no solo por tono.
- **Reserva pública:** toda blanca con líneas finas, un paso por pantalla, avatar del profesional en el resumen y acción principal fija abajo.

## Branding por empresa

- `packages/branding` convierte la marca de la empresa en variables CSS (`--brand-primary`, `--brand-primary-foreground`, `--brand-accent`, …).
- **Contraste:** si el color primario no logra 4.5:1 con el texto, se calcula el texto en blanco o negro; si ninguno cumple, se usa el color por defecto de la plataforma.
- Fallback total: una empresa sin branding usa la paleta base.
- Tipografía: 3 fuentes curadas, sin tipografías custom.
- El panel aplica el branding de la empresa del contexto; booking, el de la empresa del slug. Ambos lo leen de `GET /api/public/v1/c/:slug/branding` (con `ETag`: siempre revalida, ver [07](07-api-contract.md#marca-de-la-empresa-m204)); las imágenes salen de `/api/storage/…` ([ADR-0039](../adr/0039-archivos-de-branding-y-rutas-de-activestorage.md)). La CSP del panel permite `blob:` en `img-src` para la vista previa local de un archivo elegido.

## Accesibilidad y UX

- Componentes de shadcn/ui (Radix) con teclado y ARIA.
- Formularios con errores asociados al campo y anunciados.
- Estados vacíos, de carga y de error diseñados, no improvisados.
- Interfaz en español nicaragüense (`es-NI`); formatos de fecha, hora y moneda vía `Intl`.
