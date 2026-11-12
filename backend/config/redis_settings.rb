# Redis settings read BEFORE the app boots (config/environments/production.rb runs ahead of the initializers and cannot see
# app/), so this file is required explicitly instead of autoloaded. One place for the URL and its default, shared by the
# initializer that publishes it and by the production cache store.
module RedisSettings
  DEFAULT_URL = "redis://localhost:6379/0".freeze

  module_function

  def url = ENV.fetch("REDIS_URL", DEFAULT_URL)

  # The shared cache holds only values that can be recomputed, so it FAILS OPEN: short timeouts, no reconnects, and a Redis error
  # is logged and treated as a miss instead of failing the request.
  def cache_store_options(url: self.url)
    {
      url:, namespace: "cache", connect_timeout: 0.2, read_timeout: 0.2, write_timeout: 0.2, reconnect_attempts: 0,
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.warn({ msg: "cache.store_error", method:, error: exception.class.name }.to_json)
      }
    }
  end
end
