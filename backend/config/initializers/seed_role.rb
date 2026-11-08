# Los seeds SIEMPRE corren como app_user (el rol de la aplicación, sin BYPASSRLS), aunque se carguen dentro de
# db:prepare / db:setup / db:reset, que son tareas de esquema y corren como app_owner (config/db_roles.rb).
# Antes de cargar los seeds se reconecta como app_user y al terminar se restaura la conexión original.
module SeedAsAppUser
  def load_seed
    original = ActiveRecord::Base.connection_db_config
    return super if original.configuration_hash[:username] == "app_user"

    ActiveRecord::Base.connection_handler.clear_all_connections!
    ActiveRecord::Base.establish_connection(
      original.configuration_hash.merge(username: "app_user", password: ENV.fetch("APP_USER_PASSWORD", ""))
    )
    super
  ensure
    if original && original.configuration_hash[:username] != "app_user"
      ActiveRecord::Base.connection_handler.clear_all_connections!
      ActiveRecord::Base.establish_connection(original)
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(SeedAsAppUser)
end
