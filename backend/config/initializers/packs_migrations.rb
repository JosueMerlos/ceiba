# config/application.rb adds the packs' db/migrate to paths["db/migrate"], which only rake tasks read. Outside rake
# (check_all_pending!, maintain_test_schema!, the development pending-migrations middleware, migration_context)
# ActiveRecord::Migrator.migrations_paths is used, and it stays ["db/migrate"] unless assigned here.
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Migrator.migrations_paths = Rails.application.paths["db/migrate"].to_a
end
