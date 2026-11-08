module Api
  # `config.exceptions_app`: responde problem+json a los errores que ocurren ANTES de un controlador de la API (ruta
  # inexistente, JSON mal formado en el cuerpo) y que, por tanto, no pasan por sus `rescue_from`. Fuera de /api
  # delega en el comportamiento por defecto de Rails.
  class ExceptionsApp
    API_PATH = %r{\A/api(/|\z)}

    def call(env)
      # ShowExceptions reescribe PATH_INFO a "/404" antes de llamar a la app de excepciones: se restaura el original.
      env["PATH_INFO"] = env["action_dispatch.original_path"] if env["action_dispatch.original_path"]
      request = ActionDispatch::Request.new(env)
      return default.call(env) unless API_PATH.match?(request.path)

      exception = env["action_dispatch.exception"]
      problem = Problem.from_exception(exception, request:)
      ErrorReporter.call(exception, request_id: request.request_id, code: problem.code) if problem.status >= 500

      body = problem.to_h.to_json
      [ problem.status, { "Content-Type" => "#{Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s }, [ body ] ]
    end

    private

    def default = ActionDispatch::PublicExceptions.new(Rails.public_path)
  end
end
