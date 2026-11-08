require "rails_helper"

RSpec.describe Tenancy::Company do
  let(:organization) { new_organization }
  let(:attributes) { { name: "Barbería El Güegüense", slug: "el-guegu", business_type: "barbershop", currency: "NIO" } }

  def build_company(**overrides)
    with_tenant(organization) { described_class.new(attributes.merge(overrides)) }
  end

  def create_company(org = organization, **overrides)
    with_tenant(org) { described_class.create!(attributes.merge(overrides)) }
  end

  describe "tenant" do
    it "falla sin tenant activo (criterio 1)" do
      expect { described_class.count }.to raise_error(ActsAsTenant::Errors::NoTenantSet)
    end

    it "toma la organización del tenant activo al crear" do
      expect(create_company.organization_id).to eq(organization.id)
    end

    it "no encuentra por id una empresa de otra organización (criterio 2)" do
      other = create_company(new_organization, slug: "otra-empresa")

      expect { with_tenant(organization) { described_class.find(other.id) } }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "no cuenta las empresas de otra organización" do
      create_company(new_organization, slug: "otra-empresa")

      expect(with_tenant(organization) { described_class.count }).to eq(0)
    end

    it "rechaza una empresa asignada a otra organización" do
      company = build_company(organization_id: new_organization.id)

      expect(company).not_to be_valid
    end

    it "la base rechaza una organización inexistente aunque se salte la validación" do
      company = with_tenant(organization) { described_class.new(attributes.merge(organization_id: SecureRandom.uuid)) }

      expect { company.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_companies_organization/)
    end

    it "la base impide borrar una organización con empresas (restrict)" do
      create_company

      expect { organization.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_companies_organization/)
    end
  end

  describe "valores por defecto" do
    it "usa es-NI como locale y active como estado" do
      company = build_company

      expect(company).to have_attributes(locale: "es-NI", status: "active")
    end

    it "es válida con los datos mínimos" do
      expect(build_company).to be_valid
    end
  end

  describe "slug" do
    it "acepta letras minúsculas, dígitos y guiones de 3 a 40 caracteres" do
      %w[abc salon-1 a1b 0-0 salud-y-estilo].push("a" * 40).each do |slug|
        expect(build_company(slug:)).to be_valid, "#{slug} debería ser válido"
      end
    end

    it "rechaza formatos inválidos" do
      [ "ab", "a" * 41, "con espacio", "con_guion_bajo", "ñandú", "con.punto", "", nil ].each do |slug|
        expect(build_company(slug:)).not_to be_valid, "#{slug.inspect} debería ser inválido"
      end
    end

    it "normaliza mayúsculas y espacios en los extremos" do
      expect(build_company(slug: "  Mi-Salon ").slug).to eq("mi-salon")
    end

    it "rechaza los slugs reservados con un mensaje legible" do
      %w[api admin app www help].each do |slug|
        company = build_company(slug:)

        expect(company).not_to be_valid, "#{slug} debería estar reservado"
        expect(company.errors.details[:slug]).to include(a_hash_including(error: :exclusion))
      end
      expect(build_company(slug: "admin").errors[:slug].first).to eq("está reservado")
    end

    it "mantiene la lista de reservados en minúsculas y con formato válido o muy corto" do
      expect(described_class::RESERVED_SLUGS).to all(match(/\A[a-z0-9-]+\z/)).and include("api", "admin", "app", "c", "www", "help")
    end

    it "es único globalmente, también entre organizaciones" do
      create_company(new_organization, slug: "mi-salon")
      company = build_company(slug: "mi-salon")

      expect(company).not_to be_valid
      expect(company.errors.details[:slug]).to include(a_hash_including(error: :taken))
    end

    it "la base impide el duplicado aunque se salte la validación (carrera)" do
      create_company(new_organization, slug: "mi-salon")
      company = build_company(slug: "mi-salon")

      expect { company.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique, /uq_companies_slug/)
    end

    it "la base impide un slug reservado o mal formado aunque se salte la validación" do
      expect { build_company(slug: "Mal Formado").tap { |c| c.slug = "Mal Formado" }.save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /chk_companies_slug_format/)
    end
  end

  describe "moneda" do
    it "acepta NIO y USD" do
      %w[NIO USD].each { |currency| expect(build_company(currency:)).to be_valid }
    end

    it "rechaza otras monedas" do
      %w[EUR nio MXN].push(nil).each { |currency| expect(build_company(currency:)).not_to be_valid, "#{currency.inspect} debería ser inválida" }
    end

    it "la base rechaza otra moneda aunque se salte la validación" do
      expect { build_company(currency: "EUR").save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /chk_companies_currency/)
    end
  end

  describe "otros atributos" do
    it "exige nombre y giro" do
      expect(build_company(name: " ")).not_to be_valid
      expect(build_company(business_type: nil)).not_to be_valid
    end

    it "acepta un giro de texto libre (el giro no es un módulo, ADR-0011)" do
      expect(build_company(business_type: "dental")).to be_valid
    end

    it "limita el locale a los idiomas disponibles" do
      expect(build_company(locale: "es-NI")).to be_valid
      expect(build_company(locale: "xx-XX")).not_to be_valid
    end

    it "rechaza un estado desconocido" do
      expect(build_company(status: "borrada")).not_to be_valid
    end

    it "expone sus sucursales" do
      expect(described_class.reflect_on_association(:branches)).to be_present
    end
  end
end
