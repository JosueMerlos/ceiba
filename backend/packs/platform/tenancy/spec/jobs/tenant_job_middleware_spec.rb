require "rails_helper"

# Middleware de Sidekiq (M0.10): el organization_id viaja en el payload del job y el servidor lo envuelve en
# Tenancy.with_context. Un job sin organization_id no corre (docs/architecture/06-events-and-jobs.md).
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

    it "un job sin organization_id lanza MissingOrganization y NO ejecuta el bloque" do
      ran = false

      expect { run({ "class" => "ProbeJob" }) { ran = true } }.to raise_error(TenantJobMiddleware::MissingOrganization)
      expect(ran).to be(false)
    end

    it "un organization_id vacío cuenta como ausente" do
      expect { run({ "organization_id" => "" }) { nil } }.to raise_error(TenantJobMiddleware::MissingOrganization)
    end

    it "una organización inexistente lanza ActiveRecord::RecordNotFound" do
      expect { run({ "organization_id" => SecureRandom.uuid }) { nil } }.to raise_error(ActiveRecord::RecordNotFound)
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

    it "un payload sin organización que llega a la cola (p. ej. de una versión anterior) falla al procesarse" do
      Sidekiq::Client.push("class" => ProbeJob, "args" => [], "organization_id" => nil, "tenant" => false)
      job = ProbeJob.jobs.last.except("tenant")
      ProbeJob.jobs.replace([ job ])

      expect { ProbeJob.drain }.to raise_error(TenantJobMiddleware::MissingOrganization)
    end
  end
end
