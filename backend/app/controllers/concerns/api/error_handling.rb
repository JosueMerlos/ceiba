module Api
  # Central API rescues: every exception is rendered as problem+json. Api::ErrorRegistry maps exception -> status/code;
  # this module only renders and logs.
  module ErrorHandling
    extend ActiveSupport::Concern

    included do
      rescue_from StandardError, with: :render_problem
    end

    private

    def render_problem(exception)
      # An error raised after rendering (e.g. verify_authorized in an after_action) must not leak the built body.
      discard_rendered_body if performed?
      problem = Problem.from_exception(exception, request:)
      report(exception, problem) if problem.internal?
      render json: problem.to_h, status: problem.status, content_type: Problem::MEDIA_TYPE
    end

    # Rails cannot clear it via `response_body = nil` (it only empties the response), and a second `render` would still
    # raise DoubleRenderError.
    def discard_rendered_body
      response.reset_body!
      @_response_body = nil
    end

    # Real details (class, message, backtrace) go only to the log, keyed by request_id; never in the response, even in
    # development.
    def report(exception, problem)
      Api::ErrorReporter.call(exception, request_id: request.request_id, code: problem.code)
    end
  end
end
