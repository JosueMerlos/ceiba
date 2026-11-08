# URL de Redis compartida por Sidekiq y /api/ready. Sin valor por defecto de producción:
# en cada entorno llega por la variable REDIS_URL.
Rails.application.config.x.redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
