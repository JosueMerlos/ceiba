module Api
  # Rescates centralizados de la API: toda excepción sale como problem+json (docs/architecture/07-api-contract.md).
  # La traducción excepción -> status/code vive en Api::ErrorRegistry; aquí solo se renderiza y se registra en el log.
  module ErrorHandling
    extend ActiveSupport::Concern

    included do
      rescue_from StandardError, with: :render_problem
    end

    private

    def render_problem(exception)
      # Un error lanzado tras renderizar (p. ej. verify_authorized en un after_action) no debe dejar salir el cuerpo ya generado.
      discard_rendered_body if performed?
      problem = Problem.from_exception(exception, request:)
      report(exception, problem) if problem.internal?
      render json: problem.to_h, status: problem.status, content_type: Problem::MEDIA_TYPE
    end

    # Descarta el cuerpo ya renderizado (Rails no lo permite con `response_body = nil`: solo vacía la respuesta, y el segundo
    # `render` seguiría lanzando DoubleRenderError).
    def discard_rendered_body
      response.reset_body!
      @_response_body = nil
    end

    # El detalle real (clase, mensaje, backtrace) va SOLO al log, ligado al request_id; la respuesta no lo lleva nunca,
    # tampoco en desarrollo: quien depura busca el request_id en el log.
    def report(exception, problem)
      Api::ErrorReporter.call(exception, request_id: request.request_id, code: problem.code)
    end
  end
end
