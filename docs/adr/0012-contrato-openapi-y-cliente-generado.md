# ADR-0012: Contrato OpenAPI generado con rswag y cliente TypeScript generado

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos (API-first) |

## Contexto

API-first exige un contrato estable. Escribir los tipos del frontend a mano provoca desincronización silenciosa.

## Decisión

Los specs de **rswag** generan `openapi/v1.yaml` (commiteado). `openapi-typescript` y `openapi-fetch` generan `packages/api-client`. CI regenera ambos y falla si hay diff. Errores en `application/problem+json`, paginación por cursor y serializers con **Alba**.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| OpenAPI escrito a mano | Diseño "contract-first" puro | Doble fuente de verdad sin verificación |
| GraphQL | Flexibilidad de consulta | Complejidad de autorización por campo y caché; no hace falta |
| Tipos a mano | Cero tooling | Desincronización |

## Consecuencias

- **Positivas:** el frontend falla al compilar si la API cambia.
- **Negativas:** todo endpoint necesita un spec de rswag, lo cual también es una ventaja.
- **Obliga a:** M0.06 y el chequeo de drift en CI.

## Cuándo revisarla

No se prevé.
