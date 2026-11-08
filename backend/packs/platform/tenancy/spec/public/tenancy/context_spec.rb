require "rails_helper"

RSpec.describe Tenancy::Context do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  it "agrupa organización, empresa, sucursal y principal" do
    context = described_class.new(organization:, company:, branch:, principal: :principal)

    expect(context).to have_attributes(organization:, company:, branch:, principal: :principal)
  end

  it "solo requiere la organización" do
    context = described_class.new(organization:)

    expect(context).to have_attributes(company: nil, branch: nil, principal: nil)
  end

  it "es inmutable" do
    context = described_class.new(organization:)

    expect(context).to be_frozen
    expect { context.instance_variable_set(:@company, company) }.to raise_error(FrozenError)
    expect(context).not_to respond_to(:company=)
  end

  it "cambiar de empresa crea un contexto nuevo y no toca el original" do
    original = described_class.new(organization:, company:)
    other_company = create_in(organization, :company)

    switched = original.with(company: other_company)

    expect(switched.company).to eq(other_company)
    expect(original.company).to eq(company)
  end

  describe "coherencia (criterio 9)" do
    it "rechaza una organización ausente" do
      expect { described_class.new(organization: nil) }.to raise_error(Tenancy::InconsistentContext, /organización/)
    end

    it "rechaza una organización sin guardar" do
      expect { described_class.new(organization: Tenancy::Organization.new(name: "X")) }.to raise_error(Tenancy::InconsistentContext)
    end

    it "rechaza una empresa de otra organización" do
      foreign_company = create_in(create(:organization), :company)

      expect { described_class.new(organization:, company: foreign_company) }
        .to raise_error(Tenancy::InconsistentContext, /empresa/)
    end

    it "rechaza una sucursal que no pertenece a la empresa indicada" do
      other_company = create_in(organization, :company)
      other_branch = create_in(organization, :branch, company: other_company)

      expect { described_class.new(organization:, company:, branch: other_branch) }
        .to raise_error(Tenancy::InconsistentContext, /sucursal/)
    end

    it "rechaza una sucursal sin empresa" do
      expect { described_class.new(organization:, branch:) }.to raise_error(Tenancy::InconsistentContext, /sucursal/)
    end

    it "rechaza el cambio incoherente hecho con with" do
      context = described_class.new(organization:, company:)

      expect { context.with(company: create_in(create(:organization), :company)) }.to raise_error(Tenancy::InconsistentContext)
    end

    it "InconsistentContext es un error de dominio de Tenancy" do
      expect(Tenancy::InconsistentContext.ancestors).to include(Tenancy::Error, StandardError)
    end
  end
end
