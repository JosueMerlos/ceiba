module Observability
  # Manual Sentry check: `bin/rails sentry:test[<organization_id>]` with SENTRY_DSN set. Sends an error from the current
  # process and enqueues a failing job (run by the worker, which must also have the DSN). Both must show up in Sentry
  # with the organization_id tag (and `job`, the job's).
  module SentryCheck
    module_function

    def run(organization_id:)
      return :disabled unless Sentry.configuration.sending_allowed?

      LogContext.organization_id = organization_id
      Sentry.capture_exception(RuntimeError.new("Error de prueba de Sentry desde la consola (sentry:test)"))
      SentryTestJob.set("organization_id" => organization_id).perform_async # explicit: there is no Tenancy.with_context here
      :sent
    ensure
      LogContext.reset
    end
  end
end
