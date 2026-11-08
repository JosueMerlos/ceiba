# ADR-0030: El producto se llama Ceiba

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos: el directorio se llamaba `modular_ecosystem` (describe la arquitectura, no el producto) |

## Contexto

Hacía falta un nombre para el repositorio, el dominio, la marca y los prefijos técnicos. Criterios: no atarlo a las citas ni a un giro, corto, fácil de pronunciar en español, que permita nombrar los módulos y con dominio y marca disponibles.

## Decisión

El producto se llama **Ceiba**. Los módulos se nombran "Ceiba <Módulo>" (Ceiba Citas, …). El repositorio y el directorio son `ceiba`. El prefijo de las API keys es `cb_live_` / `cb_test_`.

El nombre del producto **no se usa en namespaces de código** (`Tenancy::`, `Appointments::`, …), para que un cambio de marca no implique un refactor.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Milpa | La metáfora más fiel de un ecosistema modular | Puede sonar rural para una clínica |
| Ometepe | Muy nicaragüense y memorable | Largo; ligado a un lugar |
| Cocibolca | Simboliza conexión | Difícil de deletrear al dictarlo |
| Raíz | Directo | Genérico; difícil de registrar y de encontrar |

## Consecuencias

- **Positivas:** identidad con raíz cultural centroamericana; una metáfora que explica la arquitectura (raíces = plataforma, ramas = módulos).
- **Riesgos abiertos (por verificar antes de invertir en marca):**
  - [ ] Dominio: `.app`, `.com`, `.com.ni` o variantes (`getceiba`, `ceibahq`).
  - [ ] Registro de marca en Nicaragua en las clases de software y servicios (Registro de la Propiedad Intelectual; confirmar la entidad competente).
  - [ ] Usuarios en Instagram y WhatsApp Business.
- Mientras no haya dominio, la documentación usa `<dominio>` como marcador.

## Cuándo revisarla

Si la verificación de marca o de dominio revela un conflicto serio. En ese caso, la alternativa preferida es **Milpa**.
