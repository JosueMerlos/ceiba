require "rails_helper"

RSpec.describe "Integración con Tenancy::ProvisionOrganization" do
  let(:attributes) do
    {
      organization: { name: "Grupo Prueba" },
      company: { name: "Salón Prueba", slug: "salon-prueba", business_type: "salon", currency: "NIO" },
      branch: { name: "Central", time_zone: "America/Managua" }
    }
  end
  let(:event_name) { "platform.organization_provisioned.v1" }

  def events_of(organization) = with_tenant(organization) { Events::OutboxEvent.where(name: event_name).to_a }

  it "el hook está registrado en ProvisionOrganization, una sola vez, con clave" do
    keyed = Tenancy::ProvisionOrganization.hooks.select { |hook| hook == Events::ProvisioningHook }

    expect(keyed.size).to eq(1)
  end

  it "registrarlo otra vez (config.to_prepare en cada recarga) no lo duplica" do
    2.times { Events::ProvisioningHook.register }

    expect(Tenancy::ProvisionOrganization.hooks.count { |hook| hook == Events::ProvisioningHook }).to eq(1)
  end

  it "al provisionar publica platform.organization_provisioned.v1 con los ids, en la organización nueva" do
    result = Tenancy::ProvisionOrganization.call(**attributes)

    expect(events_of(result.organization)).to contain_exactly(
      have_attributes(
        payload: { "organization_id" => result.organization.id, "company_id" => result.company.id, "branch_id" => result.branch.id },
        organization_id: result.organization.id,
        metadata: a_hash_including("company_id" => result.company.id, "branch_id" => result.branch.id)
      )
    )
  end

  it "si la provisión falla después del hook, no queda evento (misma transacción)" do
    failing = ->(_result) { raise "otro hook falla" }
    Tenancy::ProvisionOrganization.after_provision(failing, key: :test_failing)

    expect { Tenancy::ProvisionOrganization.call(**attributes) }.to raise_error("otro hook falla")

    expect(Tenancy::Organization.where(name: "Grupo Prueba")).to be_empty
  ensure
    Tenancy::ProvisionOrganization.remove_after_provision(failing)
  end

  it "el evento llega a un suscriptor, en el contexto de la organización nueva" do
    seen = []
    Events.subscribe(event_name, as: "test.provisioning") { |event| seen << [ event.payload["company_id"], ActsAsTenant.current_tenant.id ] }
    result = Tenancy::ProvisionOrganization.call(**attributes)

    Events::Relay.call
    Events::DeliverJob.drain

    expect(seen).to eq([ [ result.company.id, result.organization.id ] ])
  end

  describe "esquemas de módulos (M0.09 aún no existe: solo queda el esquema registrado)" do
    it "platform.module_enabled.v1 y platform.module_disabled.v1 tienen esquema con company_id y module" do
      %w[platform.module_enabled.v1 platform.module_disabled.v1].each do |name|
        expect(Events::Schemas.names).to include(name)
        expect(Events::Schemas.validate!(name, { company_id: SecureRandom.uuid, module: "appointments" })).to include("module" => "appointments")
        expect { Events::Schemas.validate!(name, { module: "appointments" }) }.to raise_error(Events::InvalidPayload)
      end
    end
  end
end
