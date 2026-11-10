module Observability
  # Rails logger formatter: ONE JSON line per entry, suitable for aggregators (Loki, CloudWatch, Datadog).
  #
  #   {"ts":"2026-11-09T12:30:15.123Z","level":"INFO","msg":"..."}                       text
  #   {"ts":"...","level":"INFO","method":"GET","status":200,"request_id":"..."}        Hash (the lograge line)
  #
  # A Hash is flattened to the root so each field is filterable without parsing `msg`. Keeps the `Rails.logger.tagged`
  # tags (`tags` list). A newline inside text comes out escaped: still ONE line.
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

    # Inside a Sidekiq job, EVERY Rails logger line (not only Sidekiq's) carries the job and its organization.
    # JobObservability::JobLogger sets them in the Sidekiq context.
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
