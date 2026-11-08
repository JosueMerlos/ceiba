# packs-rails no registra db/migrate de los packs; config/application.rb los añade a
# paths["db/migrate"], que solo leen las tareas rake. Fuera de rake (check_all_pending!,
# maintain_test_schema!, el middleware de pendientes de desarrollo, migration_context) se usa
# ActiveRecord::Migrator.migrations_paths, que sigue en ["db/migrate"] salvo que se asigne aquí.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migrator.migrations_paths = Rails.application.paths["db/migrate"].to_a
end
