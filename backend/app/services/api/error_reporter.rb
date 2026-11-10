module Api
  # Logs (and sends to Rails.error, where the error service will hook in) an exception the API answered as 5xx. The
  # only place with the real detail: the response never carries it.
  module ErrorReporter
    def self.call(exception, request_id:, code:)
      Rails.logger.error(
        "[#{request_id}] #{exception.class}: #{exception.message}\n#{Rails.backtrace_cleaner.clean(exception.backtrace || []).first(20).join("\n")}"
      )
      Rails.error.report(exception, handled: true, severity: :error, context: { request_id:, code: })
    end
  end
end
