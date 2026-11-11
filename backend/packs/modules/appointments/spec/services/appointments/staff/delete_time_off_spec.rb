require "rails_helper"

RSpec.describe Appointments::Staff::DeleteTimeOff do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:professional) { create_in(organization, :professional, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "borra la ausencia de verdad y la audita por id, SIN el motivo", :aggregate_failures do
    with_tenant(organization) do
      time_off = create(:time_off, professional:, reason: "Cirugía")
      other = create(:time_off, professional:)

      described_class.call(time_off:)

      expect(Appointments::TimeOff.pluck(:id)).to eq([ other.id ])
      event = events("time_off.deleted").sole
      expect(event.auditable_id).to eq(time_off.id)
      expect(event.before).to include("professional_id" => professional.id)
      expect(event.attributes.slice("before", "after", "metadata").to_json).not_to include("Cirug")
    end
  end

  it "no toca las ausencias de otros dueños" do
    with_tenant(organization) do
      time_off = create(:time_off, professional:)
      foreign = create(:time_off, professional: create(:professional, company:))

      described_class.call(time_off:)

      expect(Appointments::TimeOff.pluck(:id)).to eq([ foreign.id ])
    end
  end

  it "devuelve la ausencia borrada" do
    with_tenant(organization) do
      time_off = create(:time_off, professional:)

      expect(described_class.call(time_off:)).to be_destroyed
    end
  end

  it "la ausencia de un profesional o un recurso archivado no se borra (base: archived)", :aggregate_failures do
    with_tenant(organization) do
      branch = create_in(organization, :branch, company:)
      chair = create(:resource, branch:)
      owned_ids = [ create(:time_off, professional:).id, create(:time_off, resource: chair).id ]
      professional.update!(archived_at: Time.current)
      chair.update!(archived_at: Time.current)

      owned_ids.each do |id|
        time_off = Appointments::TimeOff.find(id)
        expect { described_class.call(time_off:) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:base).map(&:type)).to eq([ :archived ]) }
      end
      expect(Appointments::TimeOff.count).to eq(2)
    end
  end
end
