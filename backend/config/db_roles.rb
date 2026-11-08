# Selección del rol de base de datos (M0.04). La usa config/database.yml, que se evalúa antes de que la app
# cargue (por eso es un módulo plano en config/ y no una constante autocargada).
#
#   app_user   por defecto: servidor, worker, consola, runner, rspec, db:seed y cualquier tarea propia.
#   app_owner  solo las tareas de esquema de la ALLOWLIST de abajo (o DB_ROLE=owner explícito).
#
# REGLA: una tarea propia (rake) que cambie el esquema o la base debe AÑADIRSE a OWNER_TASKS, con revisión
# (CODEOWNERS). Cualquier otra tarea, por omisión, corre sin privilegios de dueño. Los seeds siempre corren como
# app_user, también dentro de db:prepare/db:setup/db:reset (config/initializers/seed_role.rb).
module DbRoles
  # Tareas de Rails 8.1 que crean, borran o alteran la base o su esquema. Quedan FUERA a propósito: db:seed,
  # db:seed:replant, db:fixtures:load, db:truncate_all (tareas de datos), db:migrate:status, db:version,
  # db:abort_if_pending_migrations, db:charset, db:collation (solo lectura).
  OWNER_TASKS = %w[
    db:create db:create:all db:drop db:drop:all db:purge db:purge:all
    db:migrate db:migrate:up db:migrate:down db:migrate:redo db:migrate:reset db:rollback db:forward
    db:reset db:reset:all db:setup db:setup:all db:prepare
    db:schema:load db:schema:dump db:structure:load db:structure:dump
    db:environment:set
    db:test:prepare db:test:load db:test:load_schema db:test:load_structure db:test:purge
  ].flat_map { |task| [ task, "#{task}:primary" ] }.freeze

  ROLES = %w[owner user].freeze

  module_function

  # tasks: tareas de nivel superior de rake (p. ej. ["db:migrate"] o ["db:migrate[20260101]"]).
  # override: valor de DB_ROLE (nil si no está definido).
  def select(tasks, override = nil)
    if override
      raise "DB_ROLE inválido: #{override.inspect} (owner o user)" unless ROLES.include?(override)

      return override
    end

    tasks.any? { |task| OWNER_TASKS.include?(task.to_s.sub(/\[.*\]\z/, "")) } ? "owner" : "user"
  end

  def top_level_tasks
    defined?(Rake) && Rake.respond_to?(:application) ? Rake.application.top_level_tasks : []
  end
end
