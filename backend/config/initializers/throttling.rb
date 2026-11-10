# Rack::Attack, capa 1 del rate limiting (M0.13, ADR-0027). Lógica y límites: config/middleware/rate_limiting.rb.
#
#   1  catch-all por IP            600 / 5 min   (las sondas /api/health y /api/ready no cuentan)
#   2  login por IP                  5 / 15 min
#   3  login por correo normalizado 10 / 15 min  (la clave es una huella SHA-256, nunca el correo)
#   8  404/405 de RUTA INEXISTENTE   10 / 5 min -> bloqueo de 1 h (no cuentan los 404 de negocio)
#   +  login con cuerpo > 4 KB      413 (cierra el relleno que esquivaría la regla 3)
#   La clave por IP agrupa IPv6 por /64.
#
# - Store: Redis con namespace `ratelimit:` (la URL ya fuerza la base 15 en test: config/initializers/redis.rb). Si Redis no
#   responde, RedisCacheStore devuelve nil y el límite FALLA ABIERTO (se prefiere dejar pasar a cerrar el login); queda un aviso.
# - La IP es la de ActionDispatch::RemoteIp, así que Rack::Attack va DESPUÉS de ese middleware (y de RequestId, para que el 429
#   lleve el request_id).
# - Test: desactivado por defecto (la suite hace decenas de logins desde la misma IP); spec/requests/rate_limiting_spec.rb lo
#   activa. Desarrollo: límites holgados (RateLimiting::DEVELOPMENT_LIMITS). Todos se cambian con RATE_LIMIT_<REGLA>.
require "rack/attack"
require Rails.root.join("config/middleware/rate_limiting").to_s

Rack::Attack.enabled = !Rails.env.test?

Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
  url: Rails.configuration.x.redis_url,
  namespace: "ratelimit",
  connect_timeout: 1,
  read_timeout: 0.5,
  write_timeout: 0.5,
  reconnect_attempts: 1,
  error_handler: lambda { |method:, returning:, exception:|
    Rails.logger.warn({ msg: "rate_limit.store_error", method:, error: exception.class.name }.to_json)
  }
)

Rack::Attack.blocklist("login/oversized") { |request| RateLimiting.oversized_login?(request) }
Rack::Attack.blocklist("not-found/ip") { |request| RateLimiting.banned?(request) }

Rack::Attack.throttle("catch-all/ip", limit: ->(_request) { RateLimiting.limit(:catch_all) }, period: RateLimiting.period(:catch_all)) do |request|
  RateLimiting.client_key(request) unless RateLimiting.probe?(request)
end

Rack::Attack.throttle("login/ip", limit: ->(_request) { RateLimiting.limit(:login_ip) }, period: RateLimiting.period(:login_ip)) do |request|
  RateLimiting.client_key(request) if RateLimiting.login?(request)
end

Rack::Attack.throttle("login/email", limit: ->(_request) { RateLimiting.limit(:login_email) }, period: RateLimiting.period(:login_email)) do |request|
  RateLimiting.login_email_digest(request)
end

Rack::Attack.throttled_responder = ->(request) { RateLimiting.throttled_response(request) }
Rack::Attack.blocklisted_responder = ->(request) { RateLimiting.blocklisted_response(request) }

# Una línea de log por request limitada (sin correo: la huella tampoco se escribe).
ActiveSupport::Notifications.subscribe("rack.attack") do |*, payload|
  request = payload[:request]
  next unless %i[throttle blocklist].include?(request.env["rack.attack.match_type"])

  Rails.logger.warn(
    msg: "rate_limit.#{request.env['rack.attack.match_type']}", rule: request.env["rack.attack.matched"], remote_ip: RateLimiting.ip(request),
    method: request.request_method, path: request.path, request_id: request.env["action_dispatch.request_id"]
  )
end

Rails.application.config.middleware.insert_after ActionDispatch::RemoteIp, Rack::Attack
Rails.application.config.middleware.insert_after Rack::Attack, RateLimiting::NotFoundTracker
