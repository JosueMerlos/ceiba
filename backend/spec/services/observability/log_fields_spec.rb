require "rails_helper"

# Los campos de tenant y principal de cada línea de log se leen de Current/Tenancy de forma genérica: funcionan igual hoy
# (principal mínimo de M0.07) y cuando M0.08 traiga permisos y contexto por ruta.
RSpec.describe Observability::LogFields do
  include TenancyHelpers

  after do
    Current.reset
    Observability::LogContext.reset
  end

  it "sin contexto ni principal devuelve todas las claves en nil (esquema estable)" do
    expect(described_class.current).to eq(
      organization_id: nil, company_id: nil, branch_id: nil, principal_type: nil, principal_id: nil
    )
  end

  it "con el principal de la request da su tipo y su id, y NUNCA su correo ni su nombre" do
    Current.principal = Identity::Principal::User.new(id: "u-1", email: "ana@ceiba.test", full_name: "Ana Pérez")

    fields = described_class.current

    expect(fields).to include(principal_type: "user", principal_id: "u-1")
    expect(fields.values.join).not_to include("ana@ceiba.test", "Ana")
  end

  it "recuerda el contexto de Tenancy.with_context aunque el bloque ya haya terminado (el log se escribe después)" do
    organization = new_organization
    company = create_in(organization, :company)
    branch = create_in(organization, :branch, company:)

    Tenancy.with_context(organization:, company:, branch:) { :dentro }

    expect(Current.context).to be_nil
    expect(described_class.current).to include(organization_id: organization.id, company_id: company.id, branch_id: branch.id)
  ensure
    purge_organizations(organization) if organization
  end

  it "dentro del contexto lee Current.context directamente" do
    organization = new_organization

    Tenancy.with_context(organization:) { expect(described_class.current[:organization_id]).to eq(organization.id) }
  ensure
    purge_organizations(organization) if organization
  end

  it "usa UNA sola fuente: con contexto vivo no mezcla campos recordados de otro contexto anterior" do
    organization = new_organization

    Tenancy.with_context(organization:) do
      Observability::LogContext.company_id = "empresa-de-un-contexto-anterior" # lo recordado difiere del contexto vivo
      expect(described_class.current).to include(organization_id: organization.id, company_id: nil, branch_id: nil)
    end
  ensure
    purge_organizations(organization) if organization
  end

  it "un principal sin id (p. ej. el del sistema) no rompe el log: principal_id nil y el tipo sale de su kind o su clase" do
    stub_const("Fake::Principal::System", Data.define(:kind))
    Current.principal = Fake::Principal::System.new(kind: :system)

    expect(described_class.current).to include(principal_type: "system", principal_id: nil)
  end

  it "un principal que define principal_type lo manda sobre el nombre de su clase" do
    principal = Struct.new(:id, :principal_type).new("k-1", "api_key")
    Current.principal = principal

    expect(described_class.current).to include(principal_type: "api_key", principal_id: "k-1")
  end
end
