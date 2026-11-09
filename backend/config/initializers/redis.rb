# URL de Redis compartida por Sidekiq y /api/ready. Sin valor por defecto de producción:
# en cada entorno llega por la variable REDIS_URL.
redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

# En test SIEMPRE se usa la base 15, sin importar REDIS_URL (compose da la base 0 a todos los contenedores, incluido el
# worker de desarrollo): los specs con Redis real hacen flushdb y destruyen el cron, y un worker de desarrollo consumiría
# los jobs de la suite. Comprobado en spec/config/redis_test_database_spec.rb.
if Rails.env.test?
  test_url = URI(redis_url)
  test_url.path = "/15"
  redis_url = test_url.to_s
end

Rails.application.config.x.redis_url = redis_url
