require "rails_helper"

RSpec.describe Events::ProcessedEvent do
  let(:organization) { create(:organization) }

  it "no admite dos veces el mismo suscriptor para el mismo evento" do
    with_tenant(organization) do
      processed = create(:processed_event)

      expect { savepoint { create(:processed_event, event_id: processed.event_id, subscriber: processed.subscriber) } }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it "admite el mismo evento para suscriptores distintos" do
    with_tenant(organization) do
      processed = create(:processed_event)

      expect(create(:processed_event, event_id: processed.event_id, subscriber: "otro.suscriptor")).to be_persisted
    end
  end

  describe ".older_than" do
    it "son los procesados antes del límite" do
      with_tenant(organization) do
        old = create(:processed_event, processed_at: 40.days.ago)
        create(:processed_event, processed_at: 1.day.ago)

        expect(described_class.older_than(30.days.ago)).to contain_exactly(old)
      end
    end
  end
end
