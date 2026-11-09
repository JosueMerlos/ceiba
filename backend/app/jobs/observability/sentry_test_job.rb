module Observability
  # Job que SIEMPRE falla, para comprobar a mano que un error de job llega a Sentry con organization_id y el nombre del job
  # (criterio 4 de M0.13). Lo encola `bin/rails sentry:test`; sin reintentos para no repetir el aviso.
  class SentryTestJob
    include Sidekiq::Job

    class TestError < StandardError; end

    sidekiq_options queue: "low", retry: false

    def perform = raise(TestError, "Error de prueba de Sentry desde un job (sentry:test)")
  end
end
