require "rails_helper"

RSpec.describe Appointments::ServiceResourceRequirement do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:service) { create_in(organization, :service, company:) }

  def errors_of(requirement, attribute) = requirement.errors.where(attribute).map(&:type)

  it "dice que el servicio necesita un recurso de un tipo", :aggregate_failures do
    with_tenant(organization) do
      requirement = create(:service_resource_requirement, service:, kind: "room")

      expect(requirement.reload).to have_attributes(service_id: service.id, kind: "room", company_id: company.id)
    end
  end

  it "el mismo tipo dos veces en un servicio es inválido (kind: taken) y la base de datos lo impide", :aggregate_failures do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")
      duplicate = build(:service_resource_requirement, service:, kind: "chair")

      expect(duplicate).not_to be_valid
      expect(errors_of(duplicate, :kind)).to eq([ :taken ])
      expect { savepoint { duplicate.save!(validate: false) } }.to raise_error(ActiveRecord::RecordNotUnique, /uq_srr_service_kind/)
    end
  end

  it "un servicio puede pedir varios tipos distintos y dos servicios el mismo", :aggregate_failures do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")

      expect(build(:service_resource_requirement, service:, kind: "room")).to be_valid
      expect(build(:service_resource_requirement, service: create(:service, company:), kind: "chair")).to be_valid
    end
  end

  it "rechaza un tipo desconocido (kind: inclusion) y, en la base, con el CHECK", :aggregate_failures do
    with_tenant(organization) do
      requirement = build(:service_resource_requirement, service:, kind: "spaceship")

      expect(requirement).not_to be_valid
      expect(errors_of(requirement, :kind)).to eq([ :inclusion ])
      expect { savepoint { requirement.save!(validate: false) } }.to raise_error(ActiveRecord::StatementInvalid, /chk_srr_kind/)
    end
  end

  it "un servicio de otra empresa no es el de este requisito: la FK compuesta lo impide", :aggregate_failures do
    with_tenant(organization) do
      foreign = create(:service, company: create(:company))
      requirement = build(:service_resource_requirement, service:, service_id: foreign.id)

      expect(requirement).not_to be_valid
      expect(errors_of(requirement, :service_id)).to eq([ :invalid ])
      expect { savepoint { requirement.save!(validate: false) } }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_srr_service/)
    end
  end
end
