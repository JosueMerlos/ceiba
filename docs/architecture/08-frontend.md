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
    api-client/                cliente generado desde OpenAPI + hooks de TanStack Query
    branding/                  tema por empresa: CSS vars, validación de contraste, fallback
    i18n/                      configuración de i18next y catálogos compartidos
    config/                    tsconfig, eslint, prettier y vitest compartidos
```

Las dependencias entre paquetes son explícitas en cada `package.json`. Una app nunca importa archivos de otra app.

## Stack

| Necesidad | Elección | Nota |
| --- | --- | --- |
| Build | Vite | — |
| Lenguaje | TypeScript `strict` | Sin `any` implícito |
| Router | React Router (modo data) o TanStack Router | **Decidir en M0.12** con una prueba corta; criterio: rutas lazy por módulo y loaders tipados |
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
- **Errores:** un `ApiError` con `code` se traduce por i18n; un `401` lleva al login; un `403` muestra una pantalla de permiso; un `409` en la agenda refresca y avisa "el horario ya no está disponible".

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
