# Security headers on every response. HSTS only in production: development and test are served over HTTP and the browser
# would remember the host as "HTTPS only". Rails (`force_ssl`) can also emit it; this middleware overrides its value so
# there is ONE header, with `preload`.
require Rails.root.join("config/middleware/security_headers").to_s

Rails.application.config.middleware.insert_before 0, SecurityHeaders, hsts: Rails.env.production?
