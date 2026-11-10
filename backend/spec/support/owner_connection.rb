# Connection as `app_owner` (the migrations role) for specs that need DDL.
#
# The application and the suite connect as `app_user`, which cannot create tables. The DB convention specs create test
# tables; they do it over this separate connection, which uses the same parameters as `config/database.yml` but the
# owner's credentials.
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

  # Opens an owner connection, yields it to the block and always closes it.
  def with(database: nil)
    connection = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(config(database:))
    connection.connect!
    yield connection
  ensure
    connection&.disconnect!
  end

  # Runs the block inside an owner transaction that is ALWAYS rolled back: PostgreSQL DDL is transactional, so the test
  # tables never really exist.
  def rolled_back
    with do |connection|
      connection.transaction(requires_new: true) do
        yield connection
        raise ActiveRecord::Rollback
      end
    end
  end
end
