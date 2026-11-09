# Contexto de tenant para los jobs de Sidekiq (M0.10, docs/architecture/06-events-and-jobs.md, "Jobs: reglas").
#
# - Cliente: al encolar, copia el organization_id del tenant activo al PAYLOAD del job. Un job sin tenant activo y sin
#   organization_id explícito no se encola (falla en quien lo encola, que es quien sabe de qué organización es).
# - Servidor: antes de ejecutar, abre Tenancy.with_context con esa organización (tenant de acts_as_tenant + SET LOCAL
#   app.organization_id para RLS) y lo cierra al terminar. Un payload sin organization_id lanza MissingOrganization.
#
# Los jobs del SISTEMA, que por naturaleza cruzan organizaciones (el relay, las purgas), se declaran explícitamente con
# `sidekiq_options tenant: false`. No hay una "cola tenant" implícita: las colas (critical, default, notifications, low)
# mezclan ambos tipos, así que la excepción es del job y se ve en su clase.
#
# Vive en lib/ (no se recarga): Sidekiq guarda estas clases en su cadena de middleware y una clase recargada dejaría
# referencias obsoletas. Tenancy::Organization se resuelve en el momento de la llamada.
require "sidekiq/api"
require "sidekiq/job_retry"

module TenantJobMiddleware
  KEY = "organization_id".freeze
  # Reintentos (con el backoff por defecto de Sidekiq, ~15-30 s) antes de dar por perdida una organización que no existe.
  MAX_ORGANIZATION_RETRIES = 3

  class MissingOrganization < StandardError; end

  def self.tenant_free?(job) = job["tenant"] == false

  class Client
    include Sidekiq::ClientMiddleware

    def call(job_class, job, _queue, _redis_pool)
      unless TenantJobMiddleware.tenant_free?(job)
        job[KEY] = job[KEY].presence || ActsAsTenant.current_tenant&.id ||
                   raise(MissingOrganization, "#{job_class} se encoló sin organización: encólalo dentro de Tenancy.with_context o declara `sidekiq_options tenant: false` si es un job del sistema")
      end
      yield
    end
  end

  class Server
    include Sidekiq::ServerMiddleware

    # - Sin organization_id: no se arregla reintentando; a la cola muerta de inmediato y Skip le dice al worker que ya
    #   está tratado.
    # - Organización inexistente: unos pocos reintentos (MAX_ORGANIZATION_RETRIES) por si el job se encoló dentro de la
    #   transacción que la crea y aún no es visible; agotados, a la cola muerta (no ~21 días).
    # Un error del propio job SÍ se propaga y Sidekiq lo reintenta.
    def call(worker, job, _queue, &)
      return yield if TenantJobMiddleware.tenant_free?(job)

      organization_id = job[KEY].presence
      return dead_letter!(job, MissingOrganization.new("#{worker.class} llegó sin organization_id: ningún job tenant corre sin organización")) unless organization_id

      organization = find_organization(organization_id)
      return give_up_on_missing_organization(job, organization) if organization.is_a?(Exception)

      Tenancy.with_context(organization:, &)
    end

    private

    def give_up_on_missing_organization(job, error)
      raise error if job["retry_count"].to_i < MAX_ORGANIZATION_RETRIES - 1

      dead_letter!(job, error)
    end

    # La organización, o el RecordNotFound (no lanzado) si no existe.
    def find_organization(id)
      Tenancy::Organization.find(id)
    rescue ActiveRecord::RecordNotFound => error
      error
    end

    def dead_letter!(job, error)
      failed = job.merge("error_class" => error.class.name, "error_message" => error.message.to_s[0, 10_000])
      Sidekiq::DeadSet.new.kill(Sidekiq.dump_json(failed), notify_failure: true, ex: error)
      raise Sidekiq::JobRetry::Skip
    end
  end
end
