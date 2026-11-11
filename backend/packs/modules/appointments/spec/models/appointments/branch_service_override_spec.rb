require "rails_helper"

RSpec.describe Appointments::BranchServiceOverride do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:service) { create_in(organization, :service, company:) }

  def errors_of(override, attribute) = override.errors.where(attribute).map(&:type)

  it "un override sin duración ni precio es inválido" do
    with_tenant(organization) do
      override = build(:branch_service_override, service:, branch:, duration_minutes: nil, price_minor: nil)

      expect(override).not_to be_valid
      expect(errors_of(override, :base)).to eq([ :empty ])
    end
  end

  it "con solo duración, con solo precio o con ambos es válido (precio cero incluido)" do
    with_tenant(organization) do
      expect(build(:branch_service_override, service:, branch:, duration_minutes: 40, price_minor: nil)).to be_valid
      expect(build(:branch_service_override, service:, branch:, duration_minutes: nil, price_minor: 0)).to be_valid
      expect(build(:branch_service_override, service:, branch:, duration_minutes: 40, price_minor: 500)).to be_valid
    end
  end

  it "una duración no positiva o un precio negativo es inválido" do
    with_tenant(organization) do
      expect(build(:branch_service_override, service:, branch:, duration_minutes: 0)).not_to be_valid
      expect(build(:branch_service_override, service:, branch:, duration_minutes: nil, price_minor: -1)).not_to be_valid
    end
  end

  it "el precio del override tiene el mismo tope seguro para JS: 2**53 - 1", :aggregate_failures do
    with_tenant(organization) do
      expect(build(:branch_service_override, service:, branch:, price_minor: (2**53) - 1)).to be_valid
      over = build(:branch_service_override, service:, branch:, price_minor: 2**53)

      expect(over).not_to be_valid
      expect(errors_of(over, :price_minor)).to eq([ :less_than_or_equal_to ])
    end
  end

  it "solo hay un override por sucursal y servicio" do
    with_tenant(organization) do
      create(:branch_service_override, service:, branch:)
      duplicate = build(:branch_service_override, service:, branch:)

      expect(duplicate).not_to be_valid
      expect(errors_of(duplicate, :service_id)).to eq([ :taken ])
    end
  end

  it "la misma sucursal puede tener overrides de servicios distintos y el mismo servicio de sucursales distintas" do
    with_tenant(organization) do
      create(:branch_service_override, service:, branch:)
      other_service = create(:service, company:)
      other_branch = create(:branch, company:)

      expect(build(:branch_service_override, service: other_service, branch:)).to be_valid
      expect(build(:branch_service_override, service:, branch: other_branch)).to be_valid
    end
  end

  it "una sucursal de otra empresa es un error de campo (branch_id), no una violación de FK al guardar" do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: other_company)
      override = build(:branch_service_override, service:, branch: foreign_branch)

      expect(override).not_to be_valid
      expect(errors_of(override, :branch_id)).to eq([ :invalid ])
    end
  end

  it "un servicio de otra empresa (o inexistente) es un error de campo (service_id)" do
    with_tenant(organization) do
      foreign_service = create(:service, company: other_company)
      override = build(:branch_service_override, service:, branch:, service_id: foreign_service.id)

      expect(override).not_to be_valid
      expect(errors_of(override, :service_id)).to eq([ :invalid ])
    end
  end

  it "la base de datos también lo impide: la FK compuesta rechaza una sucursal de otra empresa aunque se salte la validación" do
    with_tenant(organization) do
      foreign_branch = create(:branch, company: other_company)
      override = build(:branch_service_override, service:, branch: foreign_branch)

      expect { savepoint { override.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_bso_branch/)
    end
  end

  it "la base de datos exige duración o precio aunque se salte la validación" do
    with_tenant(organization) do
      override = build(:branch_service_override, service:, branch:, duration_minutes: nil, price_minor: nil)

      expect { savepoint { override.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /chk_bso_overrides_something/)
    end
  end
end
