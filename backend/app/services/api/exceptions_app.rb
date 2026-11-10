module Api
  # `config.exceptions_app`: answers problem+json for errors raised BEFORE an API controller (unknown route, malformed
  # JSON body, unknown HTTP method), which therefore skip its `rescue_from`. Outside /api it delegates to Rails' default
  # with the `env` INTACT (PublicExceptions derives the status from PATH_INFO, which ShowExceptions rewrote to "/<status>").
  class ExceptionsApp
    API_PATH = %r{\A/api(/|\z)}

    def call(env)
      original_path = env["action_dispatch.original_path"] || env["PATH_INFO"]
      return default.call(env) unless API_PATH.match?(original_path)

      # ShowExceptions rewrites PATH_INFO to "/404" before calling here: restore the original for `instance`.
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
