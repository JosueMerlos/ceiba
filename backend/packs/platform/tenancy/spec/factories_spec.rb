require "rails_helper"

# Las factories de tenancy derivan organization_id del PADRE, nunca lo generan por separado: así no violan las FKs
# compuestas (docs/architecture/12-testing-strategy.md, "Factories").
RSpec.describe "Factories de tenancy" do
  it "crea una organización válida" do
    expect(create(:organization)).to be_persisted
  end

  it "crea una empresa dentro del tenant activo" do
    organization = create(:organization)

    company = with_tenant(organization) { create(:company) }

    expect(company.organization_id).to eq(organization.id)
  end

  it "crea una empresa con su propia organización si se pasa organization" do
    organization = create(:organization)

    company = with_tenant(organization) { create(:company, organization:) }

    expect(company.organization).to eq(organization)
  end

  it "deriva el organization_id de la sucursal de su empresa" do
    organization = create(:organization)

    branch = with_tenant(organization) { create(:branch) }

    expect(branch.organization_id).to eq(branch.company.organization_id)
  end

  it "usa la empresa recibida y hereda su organización" do
    organization = create(:organization)

    branch = with_tenant(organization) do
      company = create(:company)
      create(:branch, company:)
    end

    expect(branch.organization_id).to eq(organization.id)
  end

  it "genera slugs únicos y válidos" do
    organization = create(:organization)

    slugs = with_tenant(organization) { create_list(:company, 3).map(&:slug) }

    expect(slugs.uniq.size).to eq(3)
  end
end
