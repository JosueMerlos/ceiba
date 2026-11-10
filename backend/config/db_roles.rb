# Database role selection, used by config/database.yml, which is evaluated before the app loads (hence a plain module
# in config/ rather than an autoloaded constant).
#
#   app_user   default: server, worker, console, runner, rspec, db:seed and any custom task.
#   app_owner  only the schema tasks in the allowlist below (or an explicit DB_ROLE=owner).
#
# RULE: a custom rake task that changes the schema or database must be ADDED to OWNER_TASKS, with review (CODEOWNERS).
# Any other task runs without owner privileges by default. Seeds always run as app_user, even inside
# db:prepare/db:setup/db:reset.
module DbRoles
  # Rails 8.1 tasks that create, drop or alter the database or its schema. Deliberately EXCLUDED: data tasks (db:seed,
  # db:seed:replant, db:fixtures:load, db:truncate_all) and read-only ones (db:migrate:status, db:version,
  # db:abort_if_pending_migrations, db:charset, db:collation).
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

  # tasks: top-level rake tasks (e.g. ["db:migrate"] or ["db:migrate[20260101]"]); override: DB_ROLE value or nil.
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
