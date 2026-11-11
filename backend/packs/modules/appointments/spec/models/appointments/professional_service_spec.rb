require "rails_helper"

RSpec.describe Appointments::ProfessionalService do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:professional) { create_in(organization, :professional, company:) }
  let(:service) { create_in(organization, :service, company:) }

  def errors_of(record, attribute) = record.errors.where(attribute).map(&:type)

  it "vincula un profesional con un servicio de su empresa" do
    with_tenant(organization) do
      link = create(:professional_service, professional:, service:)

      expect(link.reload).to have_attributes(professional_id: professional.id, service_id: service.id, company_id: company.id)
    end
  end

  it "un servicio de otra empresa es un error de campo (service_id: invalid)" do
    with_tenant(organization) do
      foreign = create(:service, company: other_company)
      link = build(:professional_service, professional:, service: foreign)

      expect(link).not_to be_valid
      expect(errors_of(link, :service_id)).to eq([ :invalid ])
    end
  end

  it "la base de datos rechaza un servicio de otra empresa aunque se salte la validación: la FK compuesta" do
    with_tenant(organization) do
      foreign = create(:service, company: other_company)
      link = build(:professional_service, professional:, service: foreign)

      expect { savepoint { link.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_ps_service/)
    end
  end

  it "un servicio archivado no se puede vincular (service_id: archived)" do
    with_tenant(organization) do
      archived = create(:service, company:, archived_at: Time.current)
      link = build(:professional_service, professional:, service: archived)

      expect(link).not_to be_valid
      expect(errors_of(link, :service_id)).to eq([ :archived ])
    end
  end

  it "vincular dos veces el mismo servicio es inválido (service_id: taken) y la base de datos también lo impide" do
    with_tenant(organization) do
      create(:professional_service, professional:, service:)
      duplicate = build(:professional_service, professional:, service:)

      expect(duplicate).not_to be_valid
      expect(errors_of(duplicate, :service_id)).to eq([ :taken ])
      expect { savepoint { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique, /uq_ps_professional_service/)
    end
  end
end
