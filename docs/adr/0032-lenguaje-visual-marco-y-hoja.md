# ADR-0032: Lenguaje visual del panel y de la reserva: marco suave con hoja blanca

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-10 |
| Origen | Revisión de diseño previa a F2: tres direcciones comparadas en maquetas (agenda del día y reserva en móvil) y extendidas al catálogo de servicios, la ficha de cliente y el inicio de sesión |

## Contexto

- El panel de M0.12 pinta toda el área de contenido con `--background: var(--palette-kapok-50)` (`#f7f8f4`), un blanco hueso verdoso. Las tarjetas blancas (`--card`) apenas se distinguen de ese fondo y el contenedor principal se percibe gris. El desarrollador quiere un contenedor principal más blanco y limpio.
- F2 trae las pantallas de trabajo diario: la agenda del día (M2.02) muestra un profesional por columna y la recepción la usa todo el día; cada píxel de ancho decide si el nombre del cliente se lee o se corta.
- La reserva pública (M3.02) se abre desde WhatsApp o Instagram en un móvil con conexión lenta: menos planos y menos peso visual es mejor.
- [ADR-0031](0031-tokens-de-diseno-en-tres-capas.md) obliga a conservar los nombres semánticos de shadcn/ui. shadcn/ui ya define la familia `--sidebar-*` y una variante "inset" de la barra lateral: el marco usa `bg-sidebar` y el contenido una hoja con `bg-background`.

## Decisión

Usaremos un **marco con tinte suave y el contenido sobre una hoja blanca** en el panel, y una reserva pública **toda blanca, estructurada con líneas finas**. Se conservan la identidad actual de `packages/ui` (verde canopy, Bricolage Grotesque en titulares y Figtree en el cuerpo; ver [08-frontend](../architecture/08-frontend.md#packagesui-y-tokens)) y el trato de "usted" de los textos actuales.

```
Panel (≥ md)                                        Reserva (móvil)
┌──────────┬────────────────────────────┬────────┐  ┌──────────────────┐
│ marco    │ hoja blanca                │ panel  │  │ negocio          │
│ (tinte)  │ título, acciones           │ contex-│  │ ▬▬▬▬▬▬▬▬▬▬▬▬░░░  │
│ logo     │                            │ tual   │  │ Elija día y hora │
│ contexto │ contenido de la pantalla   │ (colap-│  │ (●) servicio     │
│ menú     │                            │ sable) │  │ días · horas     │
│ usuario  │                            │        │  │ [  Continuar  ]  │
└──────────┴────────────────────────────┴────────┘  └──────────────────┘
```

1. **Tokens.** `--background` pasa a blanco (`--palette-kapok-0`): es la hoja del panel y el fondo de la reserva. El marco usa la familia `--sidebar-*` de shadcn/ui (`--sidebar`, `--sidebar-foreground`, `--sidebar-border`, `--sidebar-accent`, `--sidebar-accent-foreground`, `--sidebar-primary`, `--sidebar-primary-foreground`, `--sidebar-ring`), con `--sidebar` en un tinte verdoso suave (`#f2f4ef`; la primitiva `--palette-kapok-50` se ajusta a ese valor, porque `--background` deja de usarla). El ítem activo del menú es blanco sobre el marco (`--sidebar-accent`). `--sidebar-primary` y `--sidebar-ring` leen de la marca, como `--primary` y `--ring`.
2. **Estructura del panel.** Sin cabecera superior: el logo, el selector de empresa y sucursal, el menú y el usuario viven en el marco. Cada pantalla se dibuja sobre una hoja (`bg-background`, radio 16 px, borde de 1 px con `--border`, 8 px de margen al marco). Bajo `md` se mantiene la navegación en fila deslizable de M0.12.
3. **Barra lateral contraíble.** Se contrae a un riel de íconos (60 px). Cada ícono tiene `aria-label` y tooltip, y el selector de contexto queda como el monograma de la empresa. La preferencia se guarda por usuario en `localStorage`: es una comodidad visual, no un dato del negocio, y no pasa por la API. Por debajo de 1280 px de ancho arranca contraída.
4. **Panel contextual a la derecha, colapsable.** Es el único patrón para mostrar el contexto de la pantalla sin taparla: "Próximas llegadas" en la agenda (hora, estado, avatar del profesional, cliente, servicio y una acción directa) y la edición del elemento seleccionado en los catálogos. Se abre y cierra con un botón visible (`aria-expanded`, `aria-controls`). No es modal: la pantalla sigue usable con él abierto.
5. **Estados de la cita.** Se distinguen por luminosidad, no solo por tono: *llegó* (tinte verde), *confirmada* (blanco con punto verde), *por confirmar* (ámbar con borde punteado), *completada* (gris). La línea de la hora actual usa `--destructive`.
6. **Reserva pública.** Fondo blanco y líneas finas, un paso por pantalla con barra de progreso, el resumen del servicio con el **avatar del profesional** (iniciales hoy; su foto cuando exista) y la acción principal fija abajo. Objetivos táctiles de 44 px como mínimo.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Mantener el fondo `kapok-50` en todo el contenido | Sin cambios | El contenedor principal se ve gris y las tarjetas no se distinguen; es lo que motivó la revisión |
| "Papel": todo blanco, estructura solo con líneas finas | El cambio mínimo; la más limpia | Sin planos de color, en pantallas grandes todo se ve plano. **Elegida para la reserva**, donde la simplicidad pesa más |
| **"Hoja": marco con tinte y contenido sobre hoja blanca** | Contenido blanco de verdad, separado del marco sin depender de líneas; coincide con la variante "inset" de shadcn/ui | Patrón común (menos distintivo). **Elegida para el panel** |
| "Copa": riel verde oscuro solo de íconos y fecha protagonista | La de más personalidad | El riel permanente obliga a aprender los íconos. Se adoptó solo su panel de "Próximas llegadas" |

## Consecuencias

- **Positivas:** el contenido principal es blanco y se distingue del marco; la agenda gana ancho al contraer la barra y el panel contextual; un solo patrón de panel lateral sirve para la agenda y los catálogos; los nombres de tokens siguen siendo los de shadcn/ui ([ADR-0031](0031-tokens-de-diseno-en-tres-capas.md)).
- **Negativas / costos aceptados:** `AppLayout` de `packages/ui` se reescribe (la cabecera superior desaparece y su contenido pasa al marco); las capturas del E2E cambian; el marco es un patrón común, menos distintivo que "Copa".
- **Qué obliga a hacer:**
  - `packages/ui/test/tokens.test.ts` verifica también los pares de `--sidebar-*`: texto ≥ 4.5:1 sobre `--sidebar` y `--sidebar-accent`, y `--sidebar-ring` ≥ 3:1 contra `--sidebar`.
  - La validación de contraste de M2.04 compara `--brand-primary` contra `--background` (ahora blanco) **y** contra `--sidebar`.
  - Las fotos de perfil (de la persona o del profesional) no existen en el modelo de datos. Mostrarlas requiere decidir antes su almacenamiento (Active Storage, como el logo de M2.04, con las mismas validaciones de tipo y tamaño). Hasta entonces el avatar muestra iniciales.

## Cuándo revisarla

- Al añadir el modo oscuro (otro conjunto de la capa semántica, incluida `--sidebar-*`).
- Si los pilotos de F4 reportan que la agenda no cabe con la barra expandida, o si una sucursal pasa de 8 profesionales en la vista de día.
