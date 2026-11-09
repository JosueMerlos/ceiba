module Observability
  # Verificación manual de Sentry (criterio 4 de M0.13): `bin/rails sentry:test[<organization_id>]` con SENTRY_DSN definido.
  # Envía un error desde el proceso actual y encola un job que falla (lo ejecuta el worker, que también debe tener el DSN).
  # Ambos deben aparecer en Sentry con el tag organization_id (y `job`, el del job).
  module SentryCheck
    module_function

    def run(organization_id:)
      return :disabled unless Sentry.configuration.sending_allowed?

      LogContext.organization_id = organization_id
      Sentry.capture_exception(RuntimeError.new("Error de prueba de Sentry desde la consola (sentry:test)"))
      SentryTestJob.set("organization_id" => organization_id).perform_async # explícito: aquí no hay Tenancy.with_context
      :sent
    ensure
      LogContext.reset
    end
  end
end
