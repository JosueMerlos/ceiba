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
module TenantJobMiddleware
  KEY = "organization_id".freeze

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

    def call(worker, job, _queue, &)
      return yield if TenantJobMiddleware.tenant_free?(job)

      organization_id = job[KEY].presence ||
                        raise(MissingOrganization, "#{worker.class} llegó sin organization_id: ningún job tenant corre sin organización")
      Tenancy.with_context(organization: Tenancy::Organization.find(organization_id), &)
    end
  end
end
