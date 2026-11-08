redis_config = { url: Rails.configuration.x.redis_url }

Sidekiq.configure_server { |config| config.redis = redis_config }
Sidekiq.configure_client { |config| config.redis = redis_config }
