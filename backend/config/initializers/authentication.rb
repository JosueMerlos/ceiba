# Rails in API mode (`config.api_only`) does NOT ship the cookies middleware: without it `cookies[...] = ...` emits no
# Set-Cookie and the session would never reach the browser. It is added explicitly (spec/config/authentication_config_spec.rb
# checks it). Rails session and flash stay out: the session is ours, in the database.
Rails.application.config.middleware.use ActionDispatch::Cookies

# Enforces the format of API mutations (JSON, no query string) before parsing and parameter logging.
require Rails.root.join("config/middleware/api_request_guard").to_s
Rails.application.config.middleware.use ApiRequestGuard

# `Secure` cookie with the `__Host-` prefix (Secure + Path=/ + no Domain, so a subdomain cannot overwrite it).
# HTTPS only: production and staging (RAILS_ENV=production); development and test are served over HTTP.
Rails.application.config.x.auth.secure_cookies = Rails.env.production?

# Active Storage mounts its own routes (direct uploads) that bypass Api::BaseController, so they would be open without a
# session. Nothing uses files yet: draw the routes, with authentication, once something needs them.
Rails.application.config.active_storage.draw_routes = false

# Origins from which the browser may mutate (Origin/Referer validation). EXPLICIT list: never derived from Host or
# X-Forwarded-Host, which a client reaching the app port directly can forge.
#   APP_ORIGINS  comma-separated origins (e.g. "https://app.ceiba.example"). Required in production and staging.
#   development  http://localhost:<PUBLIC_PORT|8080> (the compose proxy)
#   test         http://www.example.com (the request specs' host)
# Without a value in production the list is EMPTY and every mutation carrying an Origin is rejected (fail closed).
Rails.application.config.x.auth.allowed_origins =
  if ENV["APP_ORIGINS"].present?
    ENV["APP_ORIGINS"].split(",").map { |origin| origin.strip.delete_suffix("/").downcase }.compact_blank
  elsif Rails.env.test?
    [ "http://www.example.com" ]
  elsif Rails.env.development?
    [ "http://localhost:#{ENV.fetch('PUBLIC_PORT', '8080')}" ]
  else
    []
  end
