# ADR-0001: Monolito modular con Packwerk y capas

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 (ratificada y ampliada 2026-11-07) |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3 |

## Contexto

El producto es un ecosistema de módulos que crecerá durante años y lo construye una sola persona en tiempo libre. Hacen falta límites claros entre módulos, pero sin el costo operativo de los servicios distribuidos.

## Decisión

Un solo despliegue de Rails con packs en `packs/`, verificados por **Packwerk** y por **packwerk-extensions** (checkers de privacidad y de capas). Dos capas: `platform/` (capacidades compartidas, que no conocen los módulos) y `modules/` (negocio, que depende solo de platform y se comunica por eventos). Se usa `packs-rails` para la carga.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Monolito sin límites | Lo más rápido al inicio | Se enreda; extraer después es caro |
| Rails engines | Aislamiento fuerte | Más ceremonia (gemspecs, rutas montadas, migraciones copiadas) |
| Microservicios | Escalado independiente | Red, consistencia eventual en todo y operación imposible para una persona |

## Consecuencias

- **Positivas:** transacciones locales, un solo despliegue y límites verificados en CI.
- **Negativas:** Packwerk es análisis estático; no detecta acceso por metaprogramación. Disciplina de API pública (`app/public`).
- **Obliga a:** `packwerk check` en CI, sin crecimiento de `package_todo.yml`, y un generador de packs.

## Cuándo revisarla

Si un módulo necesita escalar o desplegarse por separado con evidencia de carga real.
