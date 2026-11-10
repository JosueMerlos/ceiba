# The migration helpers are installed into the PostgreSQL adapter. They live in lib/ (not reloaded) so the adapter
# never keeps references to unloaded modules.
require_relative "../../lib/database/uuid_primary_key"
require_relative "../../lib/database/table_definition"
require_relative "../../lib/database/schema_statements"
require_relative "../../lib/database/command_recorder"

ActiveSupport.on_load(:active_record_postgresqladapter) do
  ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.prepend(Database::UuidPrimaryKey)
  ActiveRecord::ConnectionAdapters::PostgreSQL::TableDefinition.include(Database::TableDefinition)
  include Database::SchemaStatements
end

ActiveRecord::Migration::CommandRecorder.prepend(Database::CommandRecorder)
