require "rails_helper"

# Auditoría de Tenancy::ProvisionOrganization por el hook after_provision (M0.11). Tenancy no conoce a Audit: el pack se
# engancha desde config.to_prepare, igual que Events::ProvisioningHook.
RSpec.describe "Integración de Audit con Tenancy::ProvisionOrganization" do
  let(:attributes) do
    {
      organization: { name: "Grupo Prueba", legal_name: "Grupo Prueba S.A." },
      company: { name: "Salón Prueba", slug: "salon-auditado", business_type: "salon", currency: "NIO" },
      branch: { name: "Central", time_zone: "America/Managua" }
    }
  end

  def events_of(organization) = with_tenant(organization) { Audit::Event.where(action: "organization.provisioned").to_a }

  it "el hook está registrado en ProvisionOrganization, una sola vez" do
    expect(Tenancy::ProvisionOrganization.hooks.count { |hook| hook == Audit::ProvisioningHook }).to eq(1)
  end

  it "registrarlo otra vez (config.to_prepare en cada recarga) no lo duplica" do
    2.times { Audit::ProvisioningHook.register }

    expect(Tenancy::ProvisionOrganization.hooks.count { |hook| hook == Audit::ProvisioningHook }).to eq(1)
  end

  it "al provisionar audita organization.provisioned con la organización como sujeto, en la organización nueva" do
    result = Tenancy::ProvisionOrganization.call(**attributes)

    expect(events_of(result.organization)).to contain_exactly(
      have_attributes(
        organization_id: result.organization.id, auditable_type: "Tenancy::Organization", auditable_id: result.organization.id,
        actor_type: "system", before: nil, after: a_hash_including("name" => "Grupo Prueba", "country_code" => "NI"),
        metadata: { "company_id" => result.company.id, "branch_id" => result.branch.id }
      )
    )
  end

  it "usa como actor al principal que provisiona, si lo hay (operador de plataforma)" do
    operator = Identity::Principal::User.new(id: SecureRandom.uuid, email: "op@ceiba.test", full_name: "Operador")
    result = Current.set(principal: operator) { Tenancy::ProvisionOrganization.call(**attributes) }

    expect(events_of(result.organization)).to contain_exactly(have_attributes(actor_type: "user", actor_id: operator.id))
  end

  it "si la provisión falla después del hook no queda evento (misma transacción)" do
    failing = ->(_result) { raise "otro hook falla" }
    Tenancy::ProvisionOrganization.after_provision(failing)

    begin
      expect { Tenancy::ProvisionOrganization.call(**attributes) }.to raise_error("otro hook falla")
    ensure
      Tenancy::ProvisionOrganization.remove_after_provision(failing)
    end

    expect(Tenancy::Organization.where(name: "Grupo Prueba")).to be_empty
  end
end
