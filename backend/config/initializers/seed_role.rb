# Seeds ALWAYS run as app_user (the application role, without BYPASSRLS), even when loaded inside db:prepare / db:setup /
# db:reset, which are schema tasks running as app_owner. Reconnects as app_user for the seeds, then restores the original.
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
