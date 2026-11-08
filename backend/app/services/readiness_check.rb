# Comprueba las dependencias críticas con timeouts cortos para que un servicio caído
# no deje colgado el healthcheck. Los errores se registran, pero nunca se exponen en la respuesta.
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

  REDIS_TIMEOUT = 1 # segundos

  def initialize(redis_url: Rails.configuration.x.redis_url)
    @redis_url = redis_url
  end

  def call
    Result.new(checks: { database: database_up?, redis: redis_up? })
  end

  private

  def database_up?
    ActiveRecord::Base.with_connection { |connection| connection.select_value("SELECT 1") } == 1
  rescue StandardError => error
    log_failure("database", error)
  end

  def redis_up?
    client = RedisClient.config(url: @redis_url, timeout: REDIS_TIMEOUT).new_client
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
