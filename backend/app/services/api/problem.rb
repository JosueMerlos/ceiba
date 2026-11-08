module Api
  # Cuerpo de error `application/problem+json` (RFC 9457). Es la ÚNICA forma de construirlo: lo usan tanto el
  # controlador base como la app de excepciones (errores que ocurren antes de llegar a un controlador).
  #
  #   { type, title, status, code, instance, request_id }  (+ detail y errors[] cuando el error los registra)
  class Problem
    MEDIA_TYPE = "application/problem+json".freeze
    INTERNAL_CODE = "internal.error".freeze

    attr_reader :status, :code

    # Convierte una excepción en problema. Sin registro es un bug: 500 genérico, sin mensaje ni detalles.
    def self.from_exception(exception, request:)
      resolved = ErrorRegistry.resolve(exception)
      return internal(request:) unless resolved

      new(**resolved.to_h, request:)
    end

    def self.internal(request:)
      new(status: 500, code: INTERNAL_CODE, request:)
    end

    def initialize(status:, code:, request:, title: nil, detail: nil, errors: nil)
      @status = status
      @code = code
      @title = title
      @detail = detail
      @errors = errors
      @instance = request.path
      @request_id = request.request_id
    end

    def title = @title || I18n.t(code, scope: "api.errors", default: Rack::Utils::HTTP_STATUS_CODES.fetch(status))

    def to_h
      {
        type: "urn:ceiba:error:#{code}",
        title:,
        status:,
        code:,
        detail: @detail,
        instance: @instance,
        request_id: @request_id,
        errors: @errors.presence
      }.compact
    end
  end
end
