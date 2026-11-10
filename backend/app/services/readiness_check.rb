# Checks the critical dependencies with short timeouts so a down or hung service does not tie up Puma threads (and
# /api/health with them). Errors are logged, never exposed in the response.
#
# PostgreSQL is queried over its own ephemeral connection (connect_timeout + statement_timeout + hard timeout): a
# frozen server neither holds nor contaminates the Active Record pool.
class ReadinessCheck
  Result = Data.define(:checks) do
    def ready? = checks.values.all?(true)

    def to_h
      {
        status: ready? ? "ok" : "unavailable",
        checks: checks.transform_values { |up| up ? "ok" : "unavailable" }
      }
    end
  end

  TIMEOUT = 1 # seconds, per dependency

  def initialize(redis_url: Rails.configuration.x.redis_url,
                 database_config: Rails.configuration.x.readiness_database_config.presence ||
                                  ActiveRecord::Base.connection_db_config.configuration_hash)
    @redis_url = redis_url
    @database_config = database_config
  end

  def call
    Result.new(checks: { database: database_up?, redis: redis_up? })
  end

  private

  def database_up?
    Timeout.timeout(TIMEOUT + 0.5) do
      connection = PG.connect(connection_params)
      connection.exec("SELECT 1").getvalue(0, 0) == "1"
    ensure
      connection&.close
    end
  rescue StandardError => error
    log_failure("database", error)
  end

  def connection_params
    config = @database_config
    {
      host: config[:host], port: config[:port], user: config[:username], password: config[:password],
      dbname: config[:database], connect_timeout: TIMEOUT,
      options: "-c statement_timeout=#{(TIMEOUT * 1000).to_i}"
    }.compact
  end

  def redis_up?
    client = RedisClient.config(url: @redis_url, timeout: TIMEOUT).new_client
    client.call("PING") == "PONG"
  rescue StandardError => error
    log_failure("redis", error)
  ensure
    client&.close
  end

  def log_failure(dependency, error)
    Rails.logger.warn("readiness: #{dependency} no responde (#{error.class})")
    false
  end
end
