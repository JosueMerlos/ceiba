require "rails_helper"

RSpec.describe Tenancy::Branch do
  let(:organization) { new_organization }
  let(:company) { create_company(organization, "empresa-a") }

  around { |example| example.metadata[:no_tenant] ? example.run : with_tenant(organization) { example.run } }

  def create_company(org, slug)
    with_tenant(org) { Tenancy::Company.create!(name: "Empresa #{slug}", slug:, business_type: "salon", currency: "NIO") }
  end

  def build_branch(**overrides)
    described_class.new({ company:, name: "Sucursal Centro" }.merge(overrides))
  end

  def create_branch(**overrides)
    build_branch(**overrides).tap(&:save!)
  end

  describe "tenant" do
    it "falla sin tenant activo", :no_tenant do
      expect { described_class.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "toma la organización del tenant activo" do
      expect(create_branch.organization_id).to eq(organization.id)
    end

    it "no encuentra por id una sucursal de otra organización" do
      other_org = new_organization
      other_branch = with_tenant(other_org) { described_class.create!(company: create_company(other_org, "empresa-b"), name: "Otra") }

      expect { described_class.find(other_branch.id) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "valores por defecto" do
    it "usa America/Managua como zona horaria y active como estado" do
      expect(build_branch).to have_attributes(time_zone: "America/Managua", status: "active")
    end
  end

  describe "zona horaria IANA (criterio 8)" do
    it "acepta America/Managua y otras zonas IANA" do
      [ "America/Managua", "America/New_York", "Europe/Madrid", "UTC" ].each do |zone|
        expect(build_branch(time_zone: zone)).to be_valid, "#{zone} debería ser válida"
      end
    end

    it "rechaza Managua (no es IANA), vacío y basura con un error de validación" do
      [ "Managua", "", nil, "Mars/Olympus", "america/managua", "Central America" ].each do |zone|
        branch = build_branch(time_zone: zone)

        expect(branch).not_to be_valid, "#{zone.inspect} debería ser inválida"
        expect(branch.errors.details[:time_zone]).to be_present
      end
    end
  end

  describe "empresa" do
    it "exige empresa" do
      expect(build_branch(company: nil)).not_to be_valid
    end

    it "rechaza en la validación una empresa de otra organización" do
      other_company = create_company(new_organization, "empresa-b")
      branch = build_branch(company_id: other_company.id)

      expect(branch).not_to be_valid
      expect(branch.errors[:company]).to be_present
    end

    it "la base rechaza mover la sucursal a una empresa de otra organización, aunque se salte el modelo (criterio 3)" do
      branch = create_branch
      other_company = create_company(new_organization, "empresa-b")

      expect { savepoint { branch.update_columns(company_id: other_company.id) } }
        .to raise_error(ActiveRecord::InvalidForeignKey, /fk_branches_company/)
    end

    it "convierte el error de la FK compuesta en un error de validación al guardar sin validar" do
      other_company = create_company(new_organization, "empresa-b")
      branch = build_branch(company_id: other_company.id)

      expect(branch.save(validate: false)).to be(false)
      expect(branch.errors.details[:company]).to include(a_hash_including(error: :different_organization))
    end

    it "save! lanza RecordInvalid (no un error de BD) con el mismo motivo" do
      other_company = create_company(new_organization, "empresa-b")
      branch = build_branch(company_id: other_company.id)

      expect { branch.save!(validate: false) }.to raise_error(ActiveRecord::RecordInvalid, /otra organización/)
    end

    it "tras el error convertido la conexión sigue utilizable (el intento corre en un savepoint)" do
      other_company = create_company(new_organization, "empresa-b")
      build_branch(company_id: other_company.id).save(validate: false)

      expect(described_class.count).to eq(0)
    end

    it "no oculta otros errores de integridad" do
      branch = build_branch
      branch.save!
      duplicate = build_branch.tap { |b| b.id = branch.id }

      expect { savepoint { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "otros atributos" do
    it "exige nombre" do
      expect(build_branch(name: " ")).not_to be_valid
    end

    it "acepta teléfono E.164 o ninguno" do
      expect(build_branch(phone_e164: "+50588887777")).to be_valid
      expect(build_branch(phone_e164: nil)).to be_valid
    end

    it "rechaza teléfonos que no son E.164" do
      [ "88887777", "+0123456", "505 8888 7777", "+505-8888-7777" ].each do |phone|
        expect(build_branch(phone_e164: phone)).not_to be_valid, "#{phone} debería ser inválido"
      end
    end

    it "rechaza un estado desconocido" do
      expect(build_branch(status: "cerrada")).not_to be_valid
    end

    it "la base rechaza un teléfono que no es E.164 aunque se salte la validación" do
      expect { savepoint { build_branch(phone_e164: "88887777").save!(validate: false) } }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_branches_phone_e164/)
    end
  end
end
