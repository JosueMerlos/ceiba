require "rails_helper"

RSpec.describe Appointments::Staff::SetResourceRequirements do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:service) { create_in(organization, :service, company:) }

  def events(action) = Audit::Event.where(action:).to_a
  def kinds_of(service) = Appointments::ServiceResourceRequirement.where(service_id: service.id).pluck(:kind)

  it "fija el conjunto de tipos y lo audita con el antes y el después", :aggregate_failures do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")

      described_class.call(service:, kinds: %w[room equipment])

      expect(kinds_of(service)).to contain_exactly("room", "equipment")
      event = events("service.resource_requirements_set").sole
      expect([ event.before, event.after ]).to eq([ { "kinds" => [ "chair" ] }, { "kinds" => %w[equipment room] } ])
    end
  end

  it "conserva los que siguen en el conjunto (no los recrea) y los repetidos cuentan una vez", :aggregate_failures do
    with_tenant(organization) do
      kept = create(:service_resource_requirement, service:, kind: "chair")

      described_class.call(service:, kinds: %w[chair chair room])

      expect(Appointments::ServiceResourceRequirement.find(kept.id).kind).to eq("chair")
      expect(kinds_of(service)).to contain_exactly("chair", "room")
    end
  end

  it "con una lista vacía quita todos" do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")

      described_class.call(service:, kinds: [])

      expect(kinds_of(service)).to be_empty
    end
  end

  it "no audita si el conjunto no cambia" do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")

      described_class.call(service:, kinds: [ "chair" ])

      expect(events("service.resource_requirements_set")).to be_empty
    end
  end

  it "un tipo desconocido lanza RecordInvalid y no cambia nada (adversarial)", :aggregate_failures do
    with_tenant(organization) do
      create(:service_resource_requirement, service:, kind: "chair")

      expect { described_class.call(service:, kinds: %w[room spaceship]) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(kinds_of(service)).to eq([ "chair" ])
      expect(events("service.resource_requirements_set")).to be_empty
    end
  end

  it "no toca los requisitos de otro servicio" do
    with_tenant(organization) do
      other = create(:service, company:)
      create(:service_resource_requirement, service: other, kind: "chair")

      described_class.call(service:, kinds: [ "room" ])

      expect(kinds_of(other)).to eq([ "chair" ])
    end
  end
end
