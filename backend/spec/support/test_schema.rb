# Mantiene al día el esquema de la base de test (reemplaza a ActiveRecord::Migration.maintain_test_schema!).
#
# maintain_test_schema! recargaría el esquema EN PROCESO con la conexión de la suite, que es app_user (sin
# DDL). Si el esquema está desactualizado se lanza una tarea en un SUBPROCESO con DB_ROLE=owner: el rol de dueño
# queda acotado a ese proceso y la suite sigue como app_user.
#   - migraciones pendientes            -> db:prepare   (migra y vuelve a volcar structure.sql)
#   - structure.sql distinto del cargado -> db:test:prepare (recarga el esquema de test)
module TestSchema
  OWNER_ENV = { "DB_ROLE" => "owner", "RAILS_ENV" => "test", "RUN_SETUP" => "false" }.freeze

  module_function

  def ensure_current!
    run_task("db:prepare") if pending_migrations?
    run_task("db:test:prepare") if pending_migrations? || schema_changed?
    abort "Quedan migraciones pendientes: corre `make migrate`" if pending_migrations?
  end

  def run_task(task)
    # El purge de db:test:prepare borra la base: esta conexión no puede seguir abierta.
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
