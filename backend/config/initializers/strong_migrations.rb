# strong_migrations (M0.04): bloquea las migraciones que pueden tumbar producción (índices sin CONCURRENTLY,
# cambios de tipo, NOT NULL sobre tablas grandes...) y obliga a usar la variante segura.
# Se aplica en desarrollo, test y CI: spec/config/strong_migrations_spec.rb prueba el bloqueo (criterio 4).

# Las comprobaciones dependen de la versión del servidor: PostgreSQL 18 (ADR-0002).
StrongMigrations.target_version = 18

# Una migración que espera un bloqueo no debe encolar al resto de consultas detrás de ella: falla rápido...
StrongMigrations.lock_timeout = 10.seconds
# ...y ninguna sentencia de migración debe correr indefinidamente.
StrongMigrations.statement_timeout = 1.hour

# Reintenta cuando no consigue el bloqueo (lock_timeout) en lugar de abortar la migración a la primera.
StrongMigrations.lock_timeout_retries = 3
StrongMigrations.lock_timeout_retry_delay = 5.seconds

# ANALYZE tras agregar índices concurrentes, para que el planificador los use enseguida.
StrongMigrations.auto_analyze = true
