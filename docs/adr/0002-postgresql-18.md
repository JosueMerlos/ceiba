# ADR-0002: PostgreSQL 18 como motor de base de datos

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Pregunta explícita del usuario: ¿PostgreSQL o MySQL? |

## Contexto

Se buscaba un motor robusto, estable, fácil de operar, escalar y desplegar. Se evaluó MySQL como alternativa. Varias garantías críticas del diseño dependen de funciones del motor.

## Decisión

**PostgreSQL 18.**

## Alternativas consideradas

| Capacidad que el diseño usa | PostgreSQL 18 | MySQL 8/9 |
| --- | --- | --- |
| Exclusion constraints con `tstzrange` (anti doble reserva) | Sí (`btree_gist`) | No existe; habría que usar bloqueos en la aplicación |
| Row Level Security (segunda barrera entre tenants) | Sí | No existe |
| DDL transaccional (una migración fallida se revierte completa) | Sí | No; cada DDL se confirma por separado |
| `uuidv7()` nativo | Sí (desde 18) | No (`UUID()` es v1; la v7 sigue como petición abierta) |
| Índices parciales | Sí | No |
| JSONB indexable (GIN) | Sí | JSON con indexación más limitada |

Ventajas reales de MySQL (escalado horizontal con Vitess, sin VACUUM, modelo de conexiones por hilos) aparecen a escalas varios órdenes de magnitud por encima del mercado objetivo (pymes en Nicaragua).

## Consecuencias

- **Positivas:** las invariantes críticas viven en la BD; los deploys son más seguros (DDL transaccional); RLS es posible.
- **Negativas:** autovacuum debe estar sano; con mucha concurrencia hará falta PgBouncer; las actualizaciones mayores requieren `pg_upgrade`.
- **Obliga a:** usar `structure.sql`; verificar que el proveedor (si es gestionado) ofrezca PG 18 y `btree_gist`.

## Cuándo revisarla

Volúmenes de escritura que un solo nodo de PostgreSQL bien dimensionado no soporte, medidos, no supuestos.
