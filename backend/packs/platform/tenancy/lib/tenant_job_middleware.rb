# Tenant context for Sidekiq jobs.
#
# - Client: on enqueue, copies the active tenant's organization_id into the job PAYLOAD. A job with no active tenant and no
#   explicit organization_id is not enqueued (it fails at the enqueuer, who knows which organization it belongs to).
# - Server: before running, opens Tenancy.with_context with that organization (acts_as_tenant tenant + SET LOCAL
#   app.organization_id for RLS) and closes it afterwards. A payload without organization_id raises MissingOrganization.
#
# SYSTEM jobs, which by nature cross organizations (the relay, purges), are declared explicitly with
# `sidekiq_options tenant: false`. There is no implicit "tenant queue": the queues (critical, default, notifications, low)
# mix both kinds, so the exception belongs to the job and shows in its class.
#
# Lives in lib/ (not reloaded): Sidekiq keeps these classes in its middleware chain and a reloaded class would leave stale
# references. Tenancy::Organization is resolved at call time.
require "sidekiq/api"
require "sidekiq/job_retry"

module TenantJobMiddleware
  KEY = "organization_id".freeze
  # Retries (with Sidekiq's default backoff, ~15-30 s) before giving up on an organization that does not exist.
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

    # - No organization_id: retrying will not fix it; straight to the dead set, and Skip tells the worker it is handled.
    # - Nonexistent organization: a few retries (MAX_ORGANIZATION_RETRIES) in case the job was enqueued inside the
    #   transaction that creates it and is not visible yet; once exhausted, to the dead set (not ~21 days).
    # An error from the job itself DOES propagate and Sidekiq retries it.
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

    # The organization, or the RecordNotFound (returned, not raised) if it does not exist.
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
