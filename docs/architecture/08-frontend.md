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
| Fechas | `date-fns` + `@date-fns/tz` | Siempre con la zona de la **sucursal**, nunca la del navegador |
| Agenda | `AgendaView` propio sobre librería **gratuita** (react-big-calendar u otra evaluada en M2.02) | Ver abajo |
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

### i18n

`packages/i18n`: instancia **nueva** por `createI18n()` (nada global), catálogo `es-NI` tipado (una clave que no existe no compila) por namespaces (`common`, `auth`, `shell`, `errors`, `appointments`, `booking`) y formatos `Intl` (`formatCurrency` escribe "US$" para el dólar porque CLDR da "USD" en es-NI; `formatDate/Time/DateTime` exigen la zona de la sucursal). **Regla de ESLint** `i18next/no-literal-string` (eslint-plugin-i18next 6.1.5, funciona con ESLint 10) en `apps/*/src/**/*.tsx` y `packages/ui/src/**/*.tsx`, modo `jsx-only`: revisa el texto JSX y los atributos que el usuario lee (`alt`, `title`, `label`, `placeholder`, `aria-label`, `aria-description`…); los tests quedan fuera. Probada en `packages/config/test/eslint.test.ts`.

### CSRF y hooks en `@ceiba/api-client`

`createApiClient` instala un middleware: toda mutación lleva `X-CSRF-Token`; el token se captura del cuerpo de `POST /auth/login` y de `GET /auth/session` (que la SPA llama al arrancar), vive **solo en memoria** (`CsrfStore`) y se olvida al cerrar sesión o ante un `401`. Hooks base: `useSessionQuery`, `useMeQuery(contexto)`, `useOrganizationsQuery`, `useCompaniesQuery`, `useBranchesQuery`, `useLoginMutation` (con `meta.silent`: su error lo muestra el formulario), `useLogoutMutation` y `useLogoutAllMutation` (vacían la caché). `queryKeys` centraliza las claves.

### Presupuesto de bundle y E2E

- `apps/booking`: JS crítico (entrada + imports estáticos) **< 150 KiB gzip**, medido por `frontend/bin/ci-bundle` (etapa `frontend-bundle` de `bin/ci`, job de CI y `src/build.test.ts`). Hoy: **85.3 KiB** (React + i18next + la página base). `packages/config/bundle-budget.mjs` lee el manifest de Vite; los imports dinámicos no cuentan. Subir el umbral exige cambiar el ADR-0015.
- Panel: presupuesto de **220 KiB** gzip de JS crítico (medido **198.5 KiB** + ~10 % de margen; antes de la revisión eran ≈ 225 KiB). Se logró difiriendo Sentry (chunk propio, solo con DSN), quitando zod y el resolver del login (validación nativa de RHF) y cargando perezosamente el diálogo de «cerrar todas las sesiones». Los límites de ambas apps viven en `frontend/bundle-budgets.json` (una sola fuente; `bin/ci-bundle` los comprueba). **Ambos presupuestos miden solo JS** (ni CSS ni fuentes). Booking carga hoy el catálogo i18n completo (unos pocos KiB de texto): se separará por namespace cuando crezca el catálogo.
- **E2E** (`frontend/e2e`, Playwright 1.65.0): el servicio `e2e` de `compose.yaml` (perfil `e2e`, imagen `infra/docker/e2e.Dockerfile` con la misma versión de Playwright, comprobado por `check-versions.sh`) comparte la red del proxy (`network_mode: service:proxy`) y entra por `http://localhost:8080`, igual que un navegador. Corre contra los seeds de demo. `make e2e` o `bin/ci e2e`; en GitHub, el job `e2e` solo en `main` (sube el reporte y las capturas como artefacto). Los tests no escriben datos y cada uno inicia su propia sesión. Funciona con cualquier `PROXY_PORT` (Caddy escucha y publica en el mismo puerto; verificado con 38080) y la imagen no lleva etiqueta fija, así que varios entornos pueden convivir. Dependen de los **límites de Rack::Attack de desarrollo** (1000 logins por IP/15 min, `backend/config/middleware/rate_limiting.rb`): una corrida inicia ≈ 10 sesiones. Sin reintentos por defecto (`E2E_RETRIES`; el job de `main` usa 1). Seeds: `ana@multi-org.ceiba.test` está en dos organizaciones (cambio de organización), `luis@` en dos empresas, `rosa@` y `recepcion@barberia-guegu` en una sola.

## `AgendaView`: calendario detrás de un adaptador

La vista con profesionales y recursos en columnas es la pantalla más usada. FullCalendar la ofrece solo en su plan **Premium** (licencia comercial), así que se descarta.

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

## Booking (`apps/booking`)

- Ruta: `/c/:slug` (mismo origen, servida por el proxy).
- **Presupuesto:** JS crítico < 150 KB gzip, LCP < 2.5 s en 3G rápido emulado, imágenes lazy con variantes.
- Sin el design system completo: usa los tokens y unas pocas primitivas de `packages/ui`, con tree-shaking.
- Flujo: servicio(s) → profesional (o "cualquiera") → día y hora → datos (nombre y teléfono) → consentimiento → confirmación.
- Lee la configuración pública de la empresa (branding, servicios, `public_booking_enabled`) en una sola llamada cacheable.
- Envía `Idempotency-Key` generado al iniciar la confirmación (un doble tap no duplica la cita).
- CSP estricta ([11](11-security.md)).

## Lenguaje visual (F2 en adelante)

Decidido en [ADR-0032](../adr/0032-lenguaje-visual-marco-y-hoja.md), que reemplaza el layout de M0.12 a partir de F2:

- **Panel:** marco con tinte suave (`--sidebar-*`) y cada pantalla sobre una hoja blanca (`--background`). Sin cabecera superior: logo, selector de contexto, menú y usuario viven en el marco.
- **Barra lateral contraíble** a un riel de íconos, con la preferencia guardada por usuario en `localStorage`. Arranca contraída por debajo de 1280 px.
- **Panel contextual a la derecha, colapsable y no modal:** "Próximas llegadas" en la agenda y la edición del elemento seleccionado en los catálogos.
- **Estados de la cita** distinguibles por luminosidad, no solo por tono.
- **Reserva pública:** toda blanca con líneas finas, un paso por pantalla, avatar del profesional en el resumen y acción principal fija abajo.

## Branding por empresa

- `packages/branding` convierte la marca de la empresa en variables CSS (`--brand-primary`, `--brand-primary-foreground`, `--brand-accent`, …).
- **Contraste:** si el color primario no logra 4.5:1 con el texto, se calcula el texto en blanco o negro; si ninguno cumple, se usa el color por defecto de la plataforma.
- Fallback total: una empresa sin branding usa la paleta base.
- Tipografía: 3 fuentes curadas, sin tipografías custom.
- El panel aplica el branding de la empresa del contexto; booking, el de la empresa del slug.

## Accesibilidad y UX

- Componentes de shadcn/ui (Radix) con teclado y ARIA.
- Formularios con errores asociados al campo y anunciados.
- Estados vacíos, de carga y de error diseñados, no improvisados.
- Interfaz en español nicaragüense (`es-NI`); formatos de fecha, hora y moneda vía `Intl`.
