require "rails_helper"

# Alta de empresas y sucursales ADICIONALES de una organización ya provisionada (seeds, back-office M4.01): el camino
# público para no tocar los modelos privados del pack.
RSpec.describe "Alta de empresas y sucursales adicionales" do
  let(:result) do
    Tenancy::ProvisionOrganization.call(
      organization: { name: "Grupo" },
      company: { name: "Clínica", slug: "clinica-grupo", business_type: "dental", currency: "USD" },
      branch: { name: "Central" }
    )
  end

  describe Tenancy::AddCompany do
    it "crea otra empresa en la organización" do
      company = described_class.call(organization: result.organization, name: "Salón", slug: "salon-grupo", business_type: "salon", currency: "NIO")

      expect(company).to be_persisted.and have_attributes(organization_id: result.organization.id, currency: "NIO")
    end

    it "traduce un slug reservado a un error de dominio" do
      expect { described_class.call(organization: result.organization, name: "X", slug: "admin", business_type: "salon", currency: "NIO") }
        .to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:slug_reserved) }
    end

    it "traduce un slug repetido a un error de dominio" do
      expect { described_class.call(organization: result.organization, name: "X", slug: "clinica-grupo", business_type: "salon", currency: "NIO") }
        .to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:slug_taken) }
    end
  end

  describe Tenancy::AddBranch do
    it "crea otra sucursal de la empresa, con la organización derivada de ella" do
      branch = described_class.call(company: result.company, name: "Norte", time_zone: "America/Managua")

      expect(branch).to be_persisted.and have_attributes(company_id: result.company.id, organization_id: result.organization.id)
    end

    it "traduce los datos inválidos a un error de dominio" do
      expect { described_class.call(company: result.company, name: "Norte", time_zone: "Managua") }
        .to raise_error(Tenancy::ProvisioningFailed) { |error| expect(error.code).to eq(:invalid) }
    end
  end
end
