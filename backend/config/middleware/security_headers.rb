# Cabeceras de seguridad en TODA respuesta de la API (M0.13, docs/architecture/11-security.md §Transporte y cabeceras).
#
# Es un middleware y no `config.action_dispatch.default_headers` porque este solo cubre las respuestas de los controladores:
# las que generan otros middlewares antes de llegar a Rails (ApiRequestGuard, Rack::Attack, HostAuthorization) saldrían sin
# ellas. Va PRIMERO en la pila (config/initializers/security_headers.rb) y escribe al volver, así pisa valores más laxos
# (Rails pone `X-Frame-Options: SAMEORIGIN`).
#
#   X-Content-Type-Options  nosniff
#   Referrer-Policy         strict-origin-when-cross-origin
#   X-Frame-Options         DENY (navegadores sin CSP 2)
#   Content-Security-Policy frame-ancestors 'none' (la API es JSON: nunca debe incrustarse; una CSP más estricta rompería
#                           Swagger UI, que sirve scripts en línea en desarrollo, test y staging)
#   Permissions-Policy      sin cámara, micrófono, geolocalización ni pagos
#   Strict-Transport-Security solo con `hsts: true` (producción y staging, que sirven HTTPS)
#
# La CSP del panel (la que importa para XSS) la envía el proxy: infra/proxy/Caddyfile.
class SecurityHeaders
  HEADERS = {
    "X-Content-Type-Options" => "nosniff",
    "Referrer-Policy" => "strict-origin-when-cross-origin",
    "X-Frame-Options" => "DENY",
    "Content-Security-Policy" => "frame-ancestors 'none'",
    "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
  }.freeze
  HSTS = "max-age=63072000; includeSubDomains; preload".freeze

  def initialize(app, hsts: false)
    @app = app
    @headers = hsts ? HEADERS.merge("Strict-Transport-Security" => HSTS) : HEADERS
  end

  def call(env)
    status, headers, body = @app.call(env)
    @headers.each { |name, value| headers[name] = value }
    [ status, headers, body ]
  end
end
