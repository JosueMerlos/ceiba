require "rails_helper"

# acts_as_tenant 2.2.2 instala por su cuenta una extensión de Active Job que serializa el tenant actual al encolar y lo
# restaura al ejecutar SIN pasar por Tenancy.with_context (no escribe app.organization_id). Se desactiva: el único
# camino es TenantJobMiddleware (M0.10).
RSpec.describe "Extensión de Active Job de acts_as_tenant (desactivada)" do
  let(:organization) { create(:organization) }
  let(:job_class) do
    Class.new(ActiveJob::Base) do
      cattr_accessor :seen_tenant
      def perform = self.class.seen_tenant = ActsAsTenant.current_tenant
    end
  end

  before { stub_const("TenantProbeActiveJob", job_class) }

  it "no serializa el tenant en el job" do
    data = ActsAsTenant.with_tenant(organization) { TenantProbeActiveJob.new.serialize }

    expect(data).not_to have_key("current_tenant")
  end

  it "al ejecutar un job serializado dentro de un tenant, NO se restaura ese tenant" do
    data = ActsAsTenant.with_tenant(organization) { TenantProbeActiveJob.new.serialize }

    TenantProbeActiveJob.deserialize(data).perform_now

    expect(TenantProbeActiveJob.seen_tenant).to be_nil
  end

  it "un job ejecutado dentro de un tenant ajeno ve ese tenant (no se pisa ni se limpia a espaldas del contexto)" do
    ActsAsTenant.with_tenant(organization) { TenantProbeActiveJob.new.perform_now }

    expect(TenantProbeActiveJob.seen_tenant).to eq(organization)
  end

  it "canario: la gema sigue en la versión revisada (al actualizarla hay que revisar la extensión)" do
    expect(ActsAsTenant::VERSION).to eq("2.2.2")
  end
end
