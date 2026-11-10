require "rails_helper"

# Tenancy factories derive organization_id from the PARENT, never generate it separately, so they do not violate the
# composite FKs.
RSpec.describe "Factories de tenancy" do
  it "crea una organización válida" do
    expect(create(:organization)).to be_persisted
  end

  it "crea una empresa dentro del tenant activo" do
    organization = create(:organization)

    company = with_tenant(organization) { create(:company) }

    expect(company.organization_id).to eq(organization.id)
  end

  it "exige un tenant para crear una empresa (no inventa una organización)" do
    expect { create(:company) }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
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
