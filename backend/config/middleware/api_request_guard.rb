# Middleware de entrada de la API (/api/...): rechaza ANTES de que Rails parsee, enrute o registre los parámetros las
# mutaciones (POST/PUT/PATCH/DELETE) que no cumplen el formato del contrato:
#
#   - con cuerpo que no es application/json            -> 415 request.unsupported_media_type
#   - con parámetros en la query string                -> 400 request.query_not_allowed
#
# Por qué aquí y no en un before_action:
#   * Un cuerpo JSON SIN Content-Type lo parsea Rack como formulario y el log de Rails ("Parameters:") lo registra
#     como CLAVE, con la contraseña en claro (el filtro de parámetros solo oculta valores). El `Parameters:` se escribe
#     antes de cualquier before_action; en el middleware nunca llega a escribirse.
#   * Los secretos no deben viajar en la URL (quedan en logs de proxies, historial, Referer): una mutación no
#     necesita query string, todo va en el cuerpo JSON o en la ruta.
#
# La respuesta es el mismo problem+json que el resto de la API (Api::Problem). Las lecturas (GET/HEAD/OPTIONS) no se tocan.
# Se carga con require desde config/initializers/authentication.rb (config/ no es una ruta de autocarga).
class ApiRequestGuard
  API_PATH = %r{\A/api(/|\z)}
  SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    violation = violation_for(request) if API_PATH.match?(request.path_info) && !SAFE_METHODS.include?(request.request_method)
    return @app.call(env) unless violation

    respond(request, violation)
  end

  private

  def violation_for(request)
    return Api::QueryNotAllowed.new("Las mutaciones no admiten parámetros en la query string") if request.query_string.present?
    return unless body?(request) && request.media_type != "application/json"

    Api::UnsupportedMediaType.new("Las mutaciones de la API solo aceptan application/json")
  end

  def body?(request) = request.content_length.to_i.positive? || request.get_header("HTTP_TRANSFER_ENCODING").present?

  def respond(request, exception)
    problem = Api::Problem.from_exception(exception, request:)
    body = problem.to_h.to_json
    [ problem.status, { "Content-Type" => "#{Api::Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s }, [ body ] ]
  end
end
