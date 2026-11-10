# Rack::Attack, layer 1 of rate limiting. Logic and limits live in config/middleware/rate_limiting.rb.
#
#   catch-all per IP                       600 / 5 min   (the /api/health and /api/ready probes do not count)
#   login per IP                             5 / 15 min
#   login per normalized email              10 / 15 min  (the key is a SHA-256 digest, never the email)
#   404/405 on a NONEXISTENT ROUTE          10 / 5 min -> 1 h block (business 404s do not count)
#   login with a body > 4 KB                413 (closes the padding that would dodge the per-email rule)
#   The per-IP key groups IPv6 by /64.
#
# - Store: Redis with the `ratelimit:` namespace. If Redis does not answer, RedisCacheStore returns nil and the limit
#   FAILS OPEN (letting traffic through is preferred over locking out login); a warning is logged.
# - The IP comes from ActionDispatch::RemoteIp, so Rack::Attack goes AFTER that middleware (and RequestId, so the 429
#   carries the request_id).
# - Test: disabled by default (the suite does dozens of logins from the same IP); the rate limiting spec enables it.
#   Development: relaxed limits (RateLimiting::DEVELOPMENT_LIMITS). All are overridable with RATE_LIMIT_<RULE>.
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

# One log line per limited request (no email: the digest is not written either).
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
