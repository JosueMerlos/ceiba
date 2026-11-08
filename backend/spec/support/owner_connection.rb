# Conexión como `app_owner` (el rol de las migraciones) para specs que necesitan DDL.
#
# La aplicación y la suite conectan como `app_user`, que no puede crear tablas (docs/architecture/03).
# Los specs de convenciones de BD crean tablas de prueba; lo hacen con esta conexión aparte, que usa
# los mismos parámetros que `config/database.yml` pero con las credenciales del dueño.
module OwnerConnection
  OWNER = "app_owner".freeze

  module_function

  def config(database: nil)
    base = ActiveRecord::Base.connection_db_config.configuration_hash
    base.merge(
      username: OWNER,
      password: ENV.fetch("APP_OWNER_PASSWORD", ""),
      database: database || base.fetch(:database)
    )
  end

  # Abre una conexión de dueño, la cede al bloque y la cierra siempre.
  def with(database: nil)
    connection = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(config(database:))
    connection.connect!
    yield connection
  ensure
    connection&.disconnect!
  end

  # Ejecuta el bloque dentro de una transacción de dueño que SIEMPRE se revierte: el DDL de PostgreSQL
  # es transaccional, así las tablas de prueba nunca llegan a existir de verdad.
  def rolled_back
    with do |connection|
      connection.transaction(requires_new: true) do
        yield connection
        raise ActiveRecord::Rollback
      end
    end
  end
end
