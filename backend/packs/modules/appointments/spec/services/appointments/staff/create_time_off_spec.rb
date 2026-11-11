require "rails_helper"

RSpec.describe Appointments::Staff::CreateTimeOff do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  let(:attributes) { { starts_at: "2026-11-16T09:00:00Z", ends_at: "2026-11-16T13:00:00Z", reason: "Congreso médico" } }

  def events(action) = Audit::Event.where(action:).to_a

  it "crea la ausencia del profesional y la audita por id, SIN el motivo", :aggregate_failures do
    with_tenant(organization) do
      time_off = described_class.call(owner: professional, attributes:)

      expect(time_off.reload).to have_attributes(owner_type: "professional", professional_id: professional.id, resource_id: nil, company_id: company.id,
                                                 starts_at: Time.utc(2026, 11, 16, 9), ends_at: Time.utc(2026, 11, 16, 13), reason: "Congreso médico")
      event = events("time_off.created").sole
      expect(event.auditable_id).to eq(time_off.id)
      expect(event.after).to include("professional_id" => professional.id, "owner_type" => "professional")
      expect(event.attributes.slice("before", "after", "metadata").to_json).not_to include("Congreso")
      expect(event.after).not_to have_key("reason")
    end
  end

  it "crea la ausencia de un recurso", :aggregate_failures do
    with_tenant(organization) do
      time_off = described_class.call(owner: create(:resource, branch:), attributes: attributes.except(:reason))

      expect(time_off).to have_attributes(owner_type: "resource", professional_id: nil, reason: nil)
    end
  end

  it "ignora lo que un cliente no puede escribir (dueño, empresa, tipo)", :aggregate_failures do
    with_tenant(organization) do
      other = create(:professional, company:)

      time_off = described_class.call(owner: professional, attributes: attributes.merge(professional_id: other.id, owner_type: "resource", company_id: SecureRandom.uuid))

      expect(time_off).to have_attributes(professional_id: professional.id, owner_type: "professional", company_id: company.id)
    end
  end

  it "con fin anterior al inicio lanza RecordInvalid y no audita (adversarial)", :aggregate_failures do
    with_tenant(organization) do
      expect { described_class.call(owner: professional, attributes: attributes.merge(ends_at: "2026-11-16T08:00:00Z")) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Appointments::TimeOff.count).to eq(0)
      expect(events("time_off.created")).to be_empty
    end
  end

  it "un profesional o un recurso archivado no admite ausencias nuevas (base: archived)", :aggregate_failures do
    with_tenant(organization) do
      archived_professional = create(:professional, company:, archived_at: Time.current)
      archived_chair = create(:resource, branch:, archived_at: Time.current)

      [ archived_professional, archived_chair ].each do |owner|
        expect { described_class.call(owner:, attributes:) }
          .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:base).map(&:type)).to eq([ :archived ]) }
      end
      expect(Appointments::TimeOff.count).to eq(0)
    end
  end
end
