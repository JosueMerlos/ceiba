# Blocks migrations that can take production down (indexes without CONCURRENTLY, type changes, NOT NULL on large
# tables...) and forces the safe variant. Applies in development, test and CI.

# The checks depend on the server version: PostgreSQL 18.
StrongMigrations.target_version = 18

# A migration waiting for a lock must not queue other queries behind it: fail fast...
StrongMigrations.lock_timeout = 10.seconds
# ...and no migration statement may run indefinitely.
StrongMigrations.statement_timeout = 1.hour

StrongMigrations.lock_timeout_retries = 3
StrongMigrations.lock_timeout_retry_delay = 5.seconds

# ANALYZE after adding concurrent indexes so the planner uses them right away.
StrongMigrations.auto_analyze = true
