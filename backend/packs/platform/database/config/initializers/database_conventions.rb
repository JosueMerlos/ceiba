# Convenciones de BD de la plataforma (M0.04). Los helpers de migración se instalan en el adaptador de
# PostgreSQL; viven en lib/ (no se recargan) para que el adaptador no conserve referencias a módulos
# descargados. La API pública consultable (Database::TenantTables) está en app/public.
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
