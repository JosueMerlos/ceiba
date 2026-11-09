module Observability
  # Formateador del logger de Rails: UNA línea JSON por entrada, apta para agregadores (Loki, CloudWatch, Datadog).
  #
  #   {"ts":"2026-11-09T12:30:15.123Z","level":"INFO","msg":"..."}                       texto
  #   {"ts":"...","level":"INFO","method":"GET","status":200,"request_id":"..."}        Hash (la línea de lograge)
  #
  # Un Hash se aplana en la raíz para que cada campo sea filtrable sin parsear `msg`. Conserva las etiquetas de
  # `Rails.logger.tagged` (lista `tags`). Un salto de línea dentro de un texto sale escapado: sigue siendo UNA línea.
  class JsonLogFormatter < ::Logger::Formatter
    include ActiveSupport::TaggedLogging::Formatter

    def call(severity, timestamp, _progname, message)
      entry = { ts: timestamp.utc.iso8601(3), level: severity }
      entry[:tags] = current_tags.dup if current_tags.any?
      entry.merge!(job_fields)
      entry.merge!(payload_for(message))
      "#{entry.to_json}\n"
    end

    private

    # Dentro de un job de Sidekiq, TODA línea del logger de Rails (no solo las de Sidekiq) lleva el job y su organización.
    # Los pone JobObservability::JobLogger en el contexto de Sidekiq.
    def job_fields
      return {} unless defined?(Sidekiq::Context)

      context = Sidekiq::Context.current
      { jid: context[:jid], job_class: context[:class], organization_id: context[:organization_id] }.compact
    end

    def payload_for(message)
      case message
      when Hash then message.symbolize_keys
      when Exception then { msg: "#{message.class}: #{message.message}" }
      else { msg: message.to_s }
      end
    end
  end
end
