module Api
  # `config.exceptions_app`: responde problem+json a los errores que ocurren ANTES de un controlador de la API (ruta
  # inexistente, JSON mal formado en el cuerpo, método HTTP desconocido) y que, por tanto, no pasan por sus
  # `rescue_from`. Fuera de /api delega en el comportamiento por defecto de Rails con el `env` INTACTO (PublicExceptions
  # deriva el status de PATH_INFO, que ShowExceptions ya reescribió a "/<status>").
  class ExceptionsApp
    API_PATH = %r{\A/api(/|\z)}

    def call(env)
      original_path = env["action_dispatch.original_path"] || env["PATH_INFO"]
      return default.call(env) unless API_PATH.match?(original_path)

      # ShowExceptions reescribe PATH_INFO a "/404" antes de llamar aquí: para `instance` se restaura el original.
      request = ActionDispatch::Request.new(env.merge("PATH_INFO" => original_path))
      exception = env["action_dispatch.exception"]
      problem = Problem.from_exception(exception, request:)
      ErrorReporter.call(exception, request_id: request.request_id, code: problem.code) if problem.internal?

      body = problem.to_h.to_json
      [ problem.status, { "Content-Type" => "#{Problem::MEDIA_TYPE}; charset=utf-8", "Content-Length" => body.bytesize.to_s }, [ body ] ]
    end

    private

    def default = ActionDispatch::PublicExceptions.new(Rails.public_path)
  end
end
