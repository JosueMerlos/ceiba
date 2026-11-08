# ADR-0006: UUIDv7 como clave primaria en todas las tablas

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos |

## Contexto

API pública, multi-tenant y posible extracción futura de un cliente a su propia base. Los IDs secuenciales revelan volumen ("cita 1532"), permiten enumerar recursos y colisionan al mover datos entre bases.

## Decisión

PK `uuid` con default `uuidv7()` nativo de PostgreSQL 18 en todas las tablas; FKs `uuid`.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| bigint (default Rails) | Compacto, simple | Enumerable, revela volumen, colisiones entre bases |
| bigint + `public_id` con prefijo | Compacto internamente | Dos identificadores; disciplina constante |
| UUIDv4 | No adivinable | Inserciones aleatorias en el índice (fragmentación) |

## Consecuencias

- **Positivas:** ordenados por tiempo (buena localidad de índice), no adivinables y portables.
- **Negativas:** 16 bytes contra 8; URLs más largas.
- **Obliga a:** configurar los generadores (`primary_key_type: :uuid`) y usar PostgreSQL 18 en todos los entornos.

## Cuándo revisarla

No se prevé.
