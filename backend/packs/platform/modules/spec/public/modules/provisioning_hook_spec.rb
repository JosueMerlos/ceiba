require "rails_helper"

# Hook after_provision (M0.09): la organización recién provisionada nace con los módulos por defecto activos (hoy, appointments).
# Corre en la MISMA transacción que la provisión y se registra desde config.to_prepare (key: :modules_defaults).
RSpec.describe "Activación de los módulos por defecto al provisionar" do
  def provision(slug: "barberia-#{SecureRandom.hex(3)}")
    Tenancy::ProvisionOrganization.call(
      organization: { name: "Org #{slug}" }, company: { name: "Barbería", slug:, business_type: "barbershop", currency: "NIO" },
      branch: { name: "Central", time_zone: "America/Managua" }
    )
  end

  def active_keys(result) = with_tenant(result.organization) { Modules::CompanyModule.active.where(company_id: result.company.id).pluck(:module_key) }

  it "se registra como hook de la provisión" do
    expect(Tenancy::ProvisionOrganization.hooks).to include(Modules::ProvisioningHook)
  end

  it "activa appointments en la empresa nueva" do
    expect(active_keys(provision)).to eq(%w[appointments])
  end

  it "con sus settings por defecto" do
    result = provision

    expect(with_tenant(result.organization) { Modules.settings_for("appointments", company: result.company) }).to eq(Modules.registry.fetch("appointments").defaults)
  end

  it "emite platform.module_enabled.v1 y audita module.enabled como sistema, junto con la provisión" do
    result = provision
    names = with_tenant(result.organization) { Events::OutboxEvent.pluck(:name) }
    audit = with_tenant(result.organization) { Audit::Event.find_by!(action: "module.enabled") }

    expect(names).to include("platform.module_enabled.v1")
    expect(audit).to have_attributes(actor_type: "system", metadata: include("module" => "appointments"))
  end

  it "los módulos por defecto salen de la configuración (en F6, del plan)" do
    allow(Modules).to receive(:default_keys).and_return(%w[sample])
    result = provision

    expect(active_keys(result)).to eq(%w[sample])
  end

  it "una key por defecto desconocida revierte TODA la provisión" do
    allow(Modules).to receive(:default_keys).and_return(%w[fantasma])
    slug = "revierte-#{SecureRandom.hex(3)}"

    expect { provision(slug:) }.to raise_error(Modules::UnknownModule)
    expect(Tenancy::Company.unscoped.exists?(slug:)).to be(false)
  end
end
