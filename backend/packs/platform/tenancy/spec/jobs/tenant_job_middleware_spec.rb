require "rails_helper"

# Sidekiq middleware: organization_id travels in the job payload and the server wraps the job in Tenancy.with_context. A job
# without organization_id does not run.
RSpec.describe TenantJobMiddleware do
  let(:organization) { create(:organization) }
  let(:worker) { Object.new }

  describe TenantJobMiddleware::Client do
    subject(:client) { described_class.new }

    def push(job) = client.call("ProbeJob", job, "default", nil) { :pushed }

    it "añade el organization_id del tenant activo al payload" do
      job = { "class" => "ProbeJob" }

      ActsAsTenant.with_tenant(organization) { push(job) }

      expect(job["organization_id"]).to eq(organization.id)
    end

    it "respeta un organization_id explícito (p. ej. el que fija el relay)" do
      other = create(:organization)
      job = { "class" => "ProbeJob", "organization_id" => other.id }

      ActsAsTenant.with_tenant(organization) { push(job) }

      expect(job["organization_id"]).to eq(other.id)
    end

    it "sin tenant y sin organization_id lanza MissingOrganization al encolar y no encola" do
      expect { push({ "class" => "ProbeJob" }) }.to raise_error(TenantJobMiddleware::MissingOrganization, /ProbeJob/)
    end

    it "un job declarado tenant: false se encola sin organización" do
      job = { "class" => "ProbeJob", "tenant" => false }

      expect(push(job)).to eq(:pushed)
      expect(job).not_to have_key("organization_id")
    end

    it "continúa la cadena con el resultado del push" do
      ActsAsTenant.with_tenant(organization) { expect(push({ "class" => "ProbeJob" })).to eq(:pushed) }
    end
  end

  describe TenantJobMiddleware::Server do
    subject(:server) { described_class.new }

    def run(job, &block) = server.call(worker, job, "default", &block)

    it "ejecuta el job dentro de Tenancy.with_context de la organización del payload" do
      seen = nil

      run({ "organization_id" => organization.id }) do
        seen = [ ActsAsTenant.current_tenant, Current.context&.organization,
                 ApplicationRecord.connection.select_value("SELECT current_setting('app.organization_id', true)") ]
      end

      expect(seen).to eq([ organization, organization, organization.id ])
    end

    it "limpia el tenant y el setting al terminar" do
      run({ "organization_id" => organization.id }) { nil }

      expect(ActsAsTenant.current_tenant).to be_nil
      expect(ApplicationRecord.connection.select_value("SELECT current_setting('app.organization_id', true)")).to be_blank
    end

    # A retry fixes neither a job without an organization nor one for a nonexistent organization: straight to the dead set
    # (not retried for ~21 days), and the worker treats it as handled (Sidekiq::JobRetry::Skip).
    describe "errores irrecuperables", :redis do
      def dead_jobs = Sidekiq::DeadSet.new.map(&:item)

      it "un job sin organization_id va a la cola muerta y NO ejecuta el bloque" do
        ran = false

        expect { run({ "class" => "ProbeJob", "jid" => "j1" }) { ran = true } }.to raise_error(Sidekiq::JobRetry::Skip)
        expect(ran).to be(false)
        expect(dead_jobs).to contain_exactly(a_hash_including("jid" => "j1", "error_class" => "TenantJobMiddleware::MissingOrganization"))
      end

      it "un organization_id vacío cuenta como ausente" do
        expect { run({ "organization_id" => "", "jid" => "j2" }) { nil } }.to raise_error(Sidekiq::JobRetry::Skip)
        expect(dead_jobs.size).to eq(1)
      end

      it "una organización inexistente se reintenta unas pocas veces (el job pudo encolarse dentro de la transacción que la crea)" do
        job = { "organization_id" => SecureRandom.uuid, "jid" => "j3" }

        [ nil, 0, 1 ].each do |retry_count|
          expect { run(job.merge("retry_count" => retry_count).compact) { nil } }.to raise_error(ActiveRecord::RecordNotFound)
        end
        expect(dead_jobs).to be_empty
      end

      it "agotados esos reintentos, va a la cola muerta" do
        job = { "organization_id" => SecureRandom.uuid, "jid" => "j4", "retry_count" => TenantJobMiddleware::MAX_ORGANIZATION_RETRIES - 1 }

        expect { run(job) { nil } }.to raise_error(Sidekiq::JobRetry::Skip)
        expect(dead_jobs).to contain_exactly(a_hash_including("jid" => "j4", "error_class" => "ActiveRecord::RecordNotFound"))
      end

      it "una organización que aparece entre reintentos ejecuta el job" do
        organization = create(:organization)
        ran = false

        run({ "organization_id" => organization.id, "retry_count" => 1 }) { ran = true }

        expect(ran).to be(true)
      end
    end

    it "un error del propio job NO se descarta: se propaga para que Sidekiq lo reintente" do
      expect { run({ "organization_id" => organization.id }) { raise ArgumentError, "reintentable" } }.to raise_error(ArgumentError, "reintentable")
    end

    it "un job tenant: false corre sin tenant" do
      seen = :sin_ejecutar

      run({ "tenant" => false }) { seen = ActsAsTenant.current_tenant }

      expect(seen).to be_nil
    end

    it "el error del job se propaga y revierte lo que escribió en el contexto" do
      expect { run({ "organization_id" => organization.id }) { create(:company, organization:) && raise("boom") } }.to raise_error("boom")

      expect(with_tenant(organization) { Tenancy::Company.count }).to eq(0)
    end
  end

  it "canario: Sidekiq::JobRetry::Skip existe y es un Handled (API interna de la que depende el descarte)" do
    expect(Sidekiq::JobRetry::Skip.ancestors).to include(Sidekiq::JobRetry::Handled)
  end

  describe "de extremo a extremo con un job real de Sidekiq" do
    let(:probe) do
      Class.new do
        include Sidekiq::Job

        cattr_accessor :seen
        def perform = self.class.seen = [ ActsAsTenant.current_tenant&.id, Current.context&.organization&.id ]
      end
    end

    before { stub_const("ProbeJob", probe) }

    it "encolado dentro de un tenant, corre en ese tenant al procesarse" do
      ActsAsTenant.with_tenant(organization) { ProbeJob.perform_async }

      ProbeJob.drain

      expect(ProbeJob.seen).to eq([ organization.id, organization.id ])
    end

    it "encolado sin tenant falla al encolar" do
      expect { ProbeJob.perform_async }.to raise_error(TenantJobMiddleware::MissingOrganization)
    end

    it "un payload sin organización que llega a la cola (p. ej. de una versión anterior) no corre el job" do
      Sidekiq::Client.push("class" => ProbeJob, "args" => [], "tenant" => false)
      ProbeJob.jobs.replace([ ProbeJob.jobs.last.except("tenant").merge("jid" => "viejo") ])
      allow(Sidekiq::DeadSet).to receive(:new).and_return(instance_spy(Sidekiq::DeadSet))

      expect { ProbeJob.drain }.to raise_error(Sidekiq::JobRetry::Skip)
      expect(ProbeJob.seen).to be_nil
    end
  end
end
