# Sidekiq job observability: the same log schema as requests.
#
#   {"ts":"...","level":"INFO","pid":1,"tid":"1gx","msg":"done","job_class":"Events::DeliverJob","jid":"...",
#    "organization_id":"...","duration":12.4}
#
# - Formatter: one flat JSON line per log entry of the Sidekiq process (instead of Sidekiq JSON's nested `ctx`).
# - JobLogger: adds `organization_id` (from the payload, which the tenancy middleware copies on enqueue) to the log context
#   and to Observability::LogContext, so Sentry tags the error with the organization and job. Never writes `args`.
#
# Lives in config/middleware (not autoloaded): Sidekiq keeps these classes from boot and a reload would leave them stale,
# and initializers cannot use app/ constants. Observability constants are resolved at run time, not load time.
require "sidekiq"
require "sidekiq/job_logger"

module JobObservability
  # Maps Sidekiq context keys (:class, :elapsed, ...) to the request log's names.
  CONTEXT_KEYS = { class: :job_class, elapsed: :duration }.freeze

  class Formatter < Sidekiq::Logger::Formatters::Base
    def call(severity, time, _program_name, message)
      entry = { ts: time.utc.iso8601(3), level: severity, pid: ::Process.pid, tid: tid, msg: message.to_s }
      Sidekiq::Context.current.each { |key, value| entry[CONTEXT_KEYS.fetch(key.to_sym, key.to_sym)] = value }
      entry[:duration] = (entry[:duration] * 1000).round(2) if entry[:duration]
      # Same schema as requests: live tenant and principal (company_id, branch_id, principal_*).
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
