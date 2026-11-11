require "rails_helper"

RSpec.describe Appointments::Staff::ArchiveResource do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "archiva (no borra) y audita", :aggregate_failures do
    with_tenant(organization) do
      resource = create(:resource, branch:)

      freeze_time do
        described_class.call(resource:)

        expect(resource.reload.archived_at).to eq(Time.current)
      end
      expect(Appointments::Resource.where(id: resource.id)).to exist
      expect(events("resource.archived").sole.after).to include("archived_at" => be_present)
    end
  end

  it "es idempotente: archivar uno archivado no cambia la fecha ni audita otra vez", :aggregate_failures do
    with_tenant(organization) do
      resource = create(:resource, branch:)
      described_class.call(resource:)
      first = resource.reload.archived_at

      travel(1.hour) { described_class.call(resource:) }

      expect(resource.reload.archived_at).to eq(first)
      expect(events("resource.archived").size).to eq(1)
    end
  end

  it "conserva su horario y sus ausencias (la historia sigue apuntando a ellos)", :aggregate_failures do
    with_tenant(organization) do
      resource = create(:resource, branch:)
      create(:weekly_schedule, branch:, resource:)
      create(:time_off, resource:)

      described_class.call(resource:)

      expect(Appointments::WeeklySchedule.where(resource_id: resource.id).count).to eq(1)
      expect(Appointments::TimeOff.where(resource_id: resource.id).count).to eq(1)
    end
  end
end
