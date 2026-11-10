# Observabilidad de los jobs de Sidekiq (M0.13): el mismo esquema de log que las requests.
#
#   {"ts":"...","level":"INFO","pid":1,"tid":"1gx","msg":"done","job_class":"Events::DeliverJob","jid":"...",
#    "organization_id":"...","duration":12.4}
#
# - Formatter: una línea JSON plana por entrada de log del proceso Sidekiq (en lugar del anidado `ctx` del JSON de Sidekiq).
# - JobLogger: añade `organization_id` (del payload, que el middleware de tenancy copia al encolar) al contexto del log y
#   a Observability::LogContext, para que Sentry etiquete el error con la organización y el job. Nunca escribe `args`.
#
# Vive en config/middleware (no se autocarga): Sidekiq guarda estas clases al arrancar y una recarga las dejaría obsoletas, y
# los initializers no pueden usar constantes de app/. Se activa con JobObservability.install en
# config/initializers/job_logging.rb. Las constantes de Observability se resuelven al ejecutar, no al cargar.
require "sidekiq"
require "sidekiq/job_logger"

module JobObservability
  # Del contexto de Sidekiq (:class, :elapsed, ...) a los nombres del log de requests.
  CONTEXT_KEYS = { class: :job_class, elapsed: :duration }.freeze

  class Formatter < Sidekiq::Logger::Formatters::Base
    def call(severity, time, _program_name, message)
      entry = { ts: time.utc.iso8601(3), level: severity, pid: ::Process.pid, tid: tid, msg: message.to_s }
      Sidekiq::Context.current.each { |key, value| entry[CONTEXT_KEYS.fetch(key.to_sym, key.to_sym)] = value }
      entry[:duration] = (entry[:duration] * 1000).round(2) if entry[:duration]
      # Mismo esquema que las requests: tenant y principal vivos (company_id, branch_id y principal_* de LogFields).
      Observability::LogFields.current.each { |key, value| entry[key] = value if entry[key].nil? }
      "#{Sidekiq.dump_json(entry)}\n"
    end
  end

  class JobLogger < Sidekiq::JobLogger
    def prepare(job_hash, &block)
      super(job_hash) do
        organization_id = job_hash["organization_id"]
        Sidekiq::Context.add(:organization_id, organization_id)
        Observability::LogContext.organization_id = organization_id
        Observability::LogContext.job_class = job_hash["wrapped"] || job_hash["class"]
        block.call
      ensure
        Observability::LogContext.reset
      end
    end
  end

  def self.install(config)
    config.logger.formatter = Formatter.new
    config[:job_logger] = JobLogger
  end
end
