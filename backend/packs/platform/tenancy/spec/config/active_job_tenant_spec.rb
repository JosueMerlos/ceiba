require "rails_helper"

# acts_as_tenant 2.2.2 installs on its own an Active Job extension that serializes the current tenant on enqueue and
# restores it on perform WITHOUT going through Tenancy.with_context (it does not write app.organization_id). It is disabled:
# TenantJobMiddleware is the only path.
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
