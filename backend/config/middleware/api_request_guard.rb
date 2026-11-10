# API entry middleware (/api/...): BEFORE Rails parses, routes or logs parameters, rejects mutations (POST/PUT/PATCH/DELETE)
# that break the contract format:
#
#   - with a body that is not application/json   -> 415 request.unsupported_media_type
#   - with parameters in the query string        -> 400 request.query_not_allowed
#
# Why here and not in a before_action:
#   * A JSON body WITHOUT Content-Type is parsed by Rack as a form and Rails' "Parameters:" log line records it as a KEY,
#     with the password in clear (the parameter filter only hides values). "Parameters:" is written before any
#     before_action; in a middleware it is never written.
#   * Secrets must not travel in the URL (they end up in proxy logs, history, Referer): a mutation needs no query
#     string, everything goes in the JSON body or the route.
#
# Responds with the same problem+json as the rest of the API. Reads (GET/HEAD/OPTIONS) are untouched. Loaded with require
# because config/ is not an autoload path.
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
