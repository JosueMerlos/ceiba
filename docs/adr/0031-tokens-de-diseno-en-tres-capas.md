# ADR-0031: Tokens de diseño en tres capas con los nombres semánticos de shadcn/ui

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-09 |
| Origen | M0.12 (frontend shell); preferencia del usuario por tokens sistemáticos |

## Contexto

`packages/ui` lo comparten el panel y `apps/booking` ([ADR-0015](0015-reserva-publica-app-separada.md)). M2.04 aplica el branding por empresa ([ADR-0025](0025-branding-en-companies.md)) sobrescribiendo variables CSS en tiempo de ejecución. Los componentes de shadcn/ui se copian al repo ([08](../architecture/08-frontend.md)) y esperan los nombres `--background`, `--primary`, `--ring`, etc.; renombrarlos obligaría a reescribir cada componente copiado y cada actualización futura.

## Decisión

Tres capas (primitivo → semántico → componente), en `frontend/packages/ui/src/styles/tokens.css`. Dentro de la semántica, `--brand-*` es el escalón que cambia por empresa:

| Capa | Prefijo | Ejemplo | Quién la lee |
| --- | --- | --- | --- |
| Primitiva | `--palette-*` | `--palette-canopy-600: #1f7050` | Solo la capa de marca y la semántica |
| Marca | `--brand-*` | `--brand-primary: var(--palette-canopy-600)` | La capa semántica. **Es lo único que M2.04 sobrescribe por empresa** |
| Semántica | nombres de shadcn/ui | `--primary: var(--brand-primary)` | Tailwind (`@theme inline` → `bg-primary`) y los componentes |
| Componente | `--button-*`, `--input-*`, `--dialog-*`, `--nav-*` | `--button-radius: var(--radius)` | Cada componente |

Reglas:

1. **La capa semántica conserva los nombres de shadcn/ui.** `--primary`/`--secondary` (y sus `-foreground`) leen de `--brand-*`; el resto (`--background`, `--muted`, `--border`, `--ring`, `--destructive`…) lee de la paleta.
2. **`--accent` conserva su rol de shadcn** (superficie del elemento resaltado en menús y listas). El acento de marca se expone como `--highlight` (`--highlight: var(--brand-accent)`), para que un color de marca vistoso no tiña cada menú.
3. Los tokens de componente solo referencian la capa semántica, nunca la paleta ni la marca. Ningún componente usa un valor suelto.
4. Variables de marca: `--brand-primary`, `--brand-secondary`, `--brand-accent` (cada una con su `-foreground`) y `--brand-font`, que corresponden a las columnas de `companies` ([ADR-0025](0025-branding-en-companies.md)).
5. Un test (`packages/ui/test/tokens.test.ts`) verifica la estructura (toda variable de marca tiene default de paleta; la semántica lee de la marca) y el contraste WCAG AA (4.5:1) de los pares por defecto.

## Consecuencias

- **Positivas:** M2.04 cambia el tema de una empresa escribiendo ~7 variables, sin tocar componentes; los componentes de shadcn/ui se actualizan sin parches de nombres; panel y booking comparten la fuente de verdad.
- **Negativas / gotcha:** las variables semánticas se resuelven donde se DECLARAN. `--primary: var(--brand-primary)` se declara en `:root`, así que el branding debe escribirse en `:root` (`document.documentElement.style.setProperty`), no en un contenedor interior: ahí `--primary` seguiría leyendo el `--brand-primary` de `:root`. M2.04 debe respetarlo.
- No hay modo oscuro todavía; cuando exista será otro conjunto de la capa semántica (`.dark`), sin tocar la marca.
- **Obliga a:** M2.04 (`packages/branding` escribe `--brand-*` en `:root` tras validar el contraste) y a cada componente nuevo de usar solo clases semánticas.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Solo dos capas (shadcn por defecto) | Menos indirección | M2.04 tendría que sobrescribir `--primary` y compañía, mezclando "tema de plataforma" con "marca de empresa" |
| Nombres propios (`--color-action`) | Vocabulario a medida | Reescribir los componentes copiados de shadcn/ui en cada actualización |
| Branding con clases de Tailwind por empresa | — | No es posible: las empresas son datos, no código |

## Cuándo revisarla

Al implementar M2.04 o al añadir el modo oscuro.
