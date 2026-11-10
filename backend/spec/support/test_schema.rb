# Keeps the test database schema up to date (replaces ActiveRecord::Migration.maintain_test_schema!).
#
# maintain_test_schema! would reload the schema IN PROCESS over the suite's connection, which is app_user (no DDL). If
# the schema is out of date a task runs in a SUBPROCESS with DB_ROLE=owner: the owner role stays confined to that
# process and the suite keeps running as app_user.
#   - pending migrations           -> aborts asking for `make migrate`: migrating dumps db/structure.sql, which is
#                                     versioned, and the suite must not silently rewrite it
#   - structure.sql differs from loaded -> db:test:prepare (reloads the test schema)
module TestSchema
  OWNER_ENV = { "DB_ROLE" => "owner", "RAILS_ENV" => "test", "RUN_SETUP" => "false" }.freeze

  module_function

  def ensure_current!
    abort "Hay migraciones pendientes en la base de test: corre `make migrate` (migra y actualiza db/structure.sql) y `make db-prepare`" if pending_migrations?

    run_task("db:test:prepare") if schema_changed?
  end

  def run_task(task)
    # db:test:prepare's purge drops the database: this connection cannot stay open.
    ActiveRecord::Base.connection_handler.clear_all_connections!
    ok = system(OWNER_ENV, "bin/rails", task, out: File::NULL)
    abort "No se pudo preparar la base de test: corre `make db-prepare` (DB_ROLE=owner bin/rails #{task})" unless ok

    ActiveRecord::Base.connection_handler.clear_all_connections!
  end

  def pending_migrations?
    ActiveRecord::Base.connection_pool.migration_context.needs_migration?
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    true
  end

  def schema_changed?
    !ActiveRecord::Tasks::DatabaseTasks.schema_up_to_date?(ActiveRecord::Base.connection_db_config)
  end
end
