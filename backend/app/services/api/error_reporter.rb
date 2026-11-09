module Api
  # Registra en el log (y en Rails.error, donde se enganchará el servicio de errores) una excepción que la API
  # respondió como 5xx. Es el único sitio con el detalle real: la respuesta nunca lo lleva.
  module ErrorReporter
    def self.call(exception, request_id:, code:)
      Rails.logger.error(
        "[#{request_id}] #{exception.class}: #{exception.message}\n#{Rails.backtrace_cleaner.clean(exception.backtrace || []).first(20).join("\n")}"
      )
      Rails.error.report(exception, handled: true, severity: :error, context: { request_id:, code: })
    end
  end
end
