module Api
  # `application/problem+json` error body (RFC 9457). The ONLY way to build it: used by both the base controller and the
  # exceptions app (errors raised before reaching a controller).
  #
  #   { type, title, status, code, instance, request_id }  (+ detail and errors[] when the error registers them)
  class Problem
    MEDIA_TYPE = "application/problem+json".freeze
    INTERNAL_CODE = "internal.error".freeze

    attr_reader :status, :code

    # Converts an exception into a problem. Without a registration, Rails' own classification applies: a client status
    # (< 500: unknown method, invalid token...) is returned with `code: "http.<status>"`; anything else is a bug: a
    # generic 500 with no message or details.
    def self.from_exception(exception, request:)
      resolved = ErrorRegistry.resolve(exception)
      return new(**resolved.to_h, request:) if resolved

      status = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)
      return internal(request:) if status >= 500

      new(status:, code: "http.#{status}", request:)
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

    # Only a generic 500 is a bug to investigate; a 4xx (or a registered 501) is the client's and is not reported.
    def internal? = code == INTERNAL_CODE

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
