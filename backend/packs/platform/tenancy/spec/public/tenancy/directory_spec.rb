require "rails_helper"

# Tenancy::Directory: la lectura PÚBLICA de organizaciones, empresas y sucursales para otros packs (access resuelve la ruta con
# ella). Los modelos son privados; esto devuelve registros opacos y relaciones, y respeta el tenant activo.
RSpec.describe Tenancy::Directory do
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let!(:company) { create_in(organization, :company) }
  let!(:other_company) { create_in(other_organization, :company) }
  let!(:branch) { with_tenant(organization) { create(:branch, company:) } }

  describe ".organization!" do
    it "devuelve la organización (la raíz del tenant no necesita contexto)" do
      expect(described_class.organization!(organization.id)).to eq(organization)
    end

    it "lanza RecordNotFound si no existe o el id no es un UUID" do
      expect { described_class.organization!("0198f0a0-0000-7000-8000-000000000000") }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.organization!("no-es-uuid") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe ".organizations_for" do
    it "devuelve SOLO las organizaciones pedidas (no existe 'todas')" do
      expect(described_class.organizations_for([ organization.id ])).to contain_exactly(organization)
      expect(described_class.organizations_for([])).to be_empty
      expect(described_class).not_to respond_to(:organizations)
    end
  end

  describe "solo lectura" do
    it "los registros y las relaciones son readonly: no se puede guardar, actualizar ni borrar" do
      loaded = described_class.organization!(organization.id)

      expect(loaded).to be_readonly
      expect { loaded.update!(name: "Otro") }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { described_class.organizations_for([ organization.id ]).first.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "también las empresas y sucursales" do
      with_tenant(organization) do
        expect { described_class.company!(company.id).update!(name: "x") }.to raise_error(ActiveRecord::ReadOnlyRecord)
        expect { described_class.branches.first.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      end
    end
  end

  describe "empresas y sucursales: siempre dentro del tenant" do
    it "sin contexto lanzan NoTenantSet" do
      expect { described_class.companies.to_a }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
      expect { described_class.branches.to_a }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "company! solo encuentra empresas de la organización activa" do
      with_tenant(organization) do
        expect(described_class.company!(company.id)).to eq(company)
        expect { described_class.company!(other_company.id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(described_class.companies).to contain_exactly(company)
      end
    end

    it "branch! exige que la sucursal sea de la empresa indicada" do
      other_company_same_org = create_in(organization, :company)

      with_tenant(organization) do
        expect(described_class.branch!(branch.id, company_id: company.id)).to eq(branch)
        expect { described_class.branch!(branch.id, company_id: other_company_same_org.id) }.to raise_error(ActiveRecord::RecordNotFound)
        expect(described_class.branches).to contain_exactly(branch)
      end
    end
  end
end
