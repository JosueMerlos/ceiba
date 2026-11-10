module Observability
  # Job that ALWAYS fails, to check by hand that a job error reaches Sentry with organization_id and the job name.
  # Enqueued by `bin/rails sentry:test`; no retries so the alert is not repeated.
  class SentryTestJob
    include Sidekiq::Job

    class TestError < StandardError; end

    sidekiq_options queue: "low", retry: false

    def perform = raise(TestError, "Error de prueba de Sentry desde un job (sentry:test)")
  end
end
