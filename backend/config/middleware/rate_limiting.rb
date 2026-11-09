# Rate limiting capa 1 (M0.13, ADR-0027, reglas 1, 2, 3 y 8 de docs/architecture/11-security.md): Rack::Attack ANTES de
# autenticar y sin tocar la BD. Solo usa claves disponibles sin sesión: IP real, y el correo del cuerpo del login.
# La capa 2 (`rate_limit` por usuario y API key) y el resto de reglas llegan con M4.02.
#
# Este archivo concentra la lógica (límites, claves, respuestas 429) para poder probarla; las reglas se registran en
# config/initializers/throttling.rb. No se autocarga (los initializers no ven app/); Api::Problem se resuelve al responder.
require "digest"
require "json"

module RateLimiting
  LOGIN_PATH = %r{\A/api/v1/auth/login(\.\w+)?\z} # con o sin extensión de formato: Rails también la aceptaría
  PROBE_PATHS = %w[/api/health /api/ready].freeze
  MAX_LOGIN_BODY_BYTES = 4096

  # limit: peticiones por ventana; period: segundos de la ventana; ban: segundos de bloqueo (solo la regla 8).
  RULES = {
    catch_all: { limit: 600, period: 5.minutes.to_i },
    login_ip: { limit: 5, period: 15.minutes.to_i },
    login_email: { limit: 10, period: 15.minutes.to_i },
    not_found: { limit: 10, period: 5.minutes.to_i, ban: 1.hour.to_i }
  }.freeze
  # Desarrollo holgado (un desarrollador equivoca la contraseña más de 5 veces); test no se limita (ver throttling.rb).
  DEVELOPMENT_LIMITS = { catch_all: 100_000, login_ip: 1000, login_email: 1000, not_found: 100_000 }.freeze

  module_function

  # RATE_LIMIT_<REGLA> (p. ej. RATE_LIMIT_LOGIN_IP=20) cambia el límite sin redeploy de código.
  def limit(rule)
    configured = ENV["RATE_LIMIT_#{rule.to_s.upcase}"]
    return Integer(configured) if configured.present?

    Rails.env.development? ? DEVELOPMENT_LIMITS.fetch(rule) : RULES.fetch(rule).fetch(:limit)
  end

  def period(rule) = RULES.fetch(rule).fetch(:period)

  # La IP del CLIENTE tal como la resuelve ActionDispatch::RemoteIp (proxies de confianza), no Rack::Request#ip. Si resolverla
  # lanza IpSpoofAttackError (cabeceras de reenvío contradictorias) se usa la dirección del par: el 500 sería peor.
  def ip(request)
    (request.env["action_dispatch.remote_ip"] || request.ip).to_s
  rescue ActionDispatch::RemoteIp::IpSpoofAttackError
    request.env["REMOTE_ADDR"].to_s
  end

  # Clave de límite por cliente: IPv4 tal cual; IPv6 agrupada por /64 (a un cliente le asignan al menos un /64 y rotar
  # direcciones dentro de él no debe darle un límite nuevo cada vez).
  def client_key(request)
    address = IPAddr.new(ip(request))
    address.ipv6? && !address.ipv4_mapped? ? "#{address.mask(64)}/64" : address.to_s
  rescue IPAddr::InvalidAddressError
    ip(request)
  end

  def oversized_login?(request)
    login?(request) && (request.content_length.to_i > MAX_LOGIN_BODY_BYTES || request.get_header("HTTP_TRANSFER_ENCODING").present?)
  end

  def probe?(request) = PROBE_PATHS.include?(request.path)

  def login?(request) = request.post? && LOGIN_PATH.match?(request.path)

  # Huella del correo normalizado (como Identity::User): el correo nunca se guarda en Redis. Solo lee cuerpos JSON pequeños.
  def login_email_digest(request)
    return unless login?(request) && request.media_type == "application/json"
    return unless request.content_length.to_i.between?(1, MAX_LOGIN_BODY_BYTES) # los mayores se rechazan antes (413)

    body = request.body.read(MAX_LOGIN_BODY_BYTES)
    request.body.rewind
    email = JSON.parse(body.to_s)["email"] if body.to_s.lstrip.start_with?("{")
    Digest::SHA256.hexdigest(email.strip.downcase) if email.is_a?(String) && email.present?
  rescue JSON::ParserError
    nil
  end

  def ban_key(request) = "ban:not-found:#{client_key(request)}"

  # El valor guardado es el instante en que termina el bloqueo; se compara con el reloj además del TTL de Redis.
  def banned?(request) = Rack::Attack.cache.read(ban_key(request)).to_i > Time.now.to_i

  # 429 de un throttle: la ventana en curso (`rack.attack.match_data`).
  def throttled_response(request)
    data = request.env["rack.attack.match_data"]
    retry_after = (data[:period] - (data[:epoch_time] % data[:period])).to_i
    respond(request, code: "rate_limit.exceeded", retry_after:, limit: data[:limit])
  end

  # Respuesta del blocklist: el cuerpo de login demasiado grande (413) o el bloqueo de la regla 8 (429).
  def blocklisted_response(request)
    return request_too_large(request) if request.env["rack.attack.matched"] == "login/oversized"

    blocked_response(request)
  end

  # Un login real mide unas decenas de bytes. Un cuerpo mayor (relleno para que el correo quede fuera de lo que se lee y
  # esquivar la regla 3) se rechaza sin parsearlo. Transfer-Encoding (sin longitud conocida) también.
  def request_too_large(request)
    problem = Api::Problem.new(status: 413, code: "request.too_large", request: ActionDispatch::Request.new(request.env))
    body = problem.to_h.to_json
    [ 413, { "Content-Type" => "#{Api::Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s }, [ body ] ]
  end

  # 429 de un bloqueo (regla 8): el valor guardado es el instante en que termina.
  def blocked_response(request)
    until_epoch = Rack::Attack.cache.read(ban_key(request)).to_i
    retry_after = [ until_epoch - Time.now.to_i, 1 ].max
    respond(request, code: "rate_limit.blocked", retry_after:, limit: limit(:not_found))
  end

  def respond(request, code:, retry_after:, limit:)
    problem = Api::Problem.new(status: 429, code:, request: ActionDispatch::Request.new(request.env))
    body = problem.to_h.to_json
    headers = {
      "Content-Type" => "#{Api::Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s,
      "Retry-After" => retry_after.to_s, "RateLimit-Limit" => limit.to_s, "RateLimit-Remaining" => "0", "RateLimit-Reset" => retry_after.to_s
    }
    [ 429, headers, [ body ] ]
  end

  # Regla 8: cuenta por IP las respuestas de RUTA INEXISTENTE (ActionController::RoutingError, o método HTTP desconocido) y, al
  # llegar al límite, escribe el bloqueo. NO cuenta los 404 de negocio (recurso no visible, contexto inconsistente): los
  # provoca un usuario legítimo y una clínica entera comparte IP. Va justo DENTRO de Rack::Attack (necesita la respuesta de la
  # aplicación, que un blocklist no ve): la lista de bloqueo lee la marca que aquí se escribe. Rails deja la excepción en
  # `action_dispatch.exception` cuando la delega en la app de excepciones; los 404 que un controlador rescata no la dejan.
  class NotFoundTracker
    def initialize(app) = @app = app

    def call(env)
      response = @app.call(env)
      record(env) if Rack::Attack.enabled && [ 404, 405 ].include?(response.first) && routing_failure?(env)
      response
    end

    private

    ROUTING_ERRORS = [ ActionController::RoutingError, ActionController::UnknownHttpMethod ].freeze

    def routing_failure?(env) = ROUTING_ERRORS.any? { |error| env["action_dispatch.exception"].is_a?(error) }

    def record(env)
      request = Rack::Attack::Request.new(env)
      count = Rack::Attack.cache.count("not-found:#{RateLimiting.client_key(request)}", RateLimiting.period(:not_found))
      return if count < RateLimiting.limit(:not_found)

      ban = RateLimiting::RULES.dig(:not_found, :ban)
      Rack::Attack.cache.write(RateLimiting.ban_key(request), Time.now.to_i + ban, ban)
    end
  end
end
