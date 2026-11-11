require "rails_helper"

RSpec.describe Appointments::Catalog::ArchiveService do
  include ActiveSupport::Testing::TimeHelpers

  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }

  def events(action) = Audit::Event.where(action:).to_a

  it "fija archived_at, conserva la fila y la saca del catálogo" do
    with_tenant(organization) do
      service = create(:service, company:)

      travel_to(Time.zone.local(2026, 11, 10, 15, 0, 0)) { described_class.call(service:) }

      expect(Appointments::Service.find(service.id).archived_at).to eq(Time.zone.local(2026, 11, 10, 15, 0, 0))
      expect(Appointments::Service.where(company_id: company.id).unarchived).to be_empty
      expect(Appointments::Service.where(id: service.id)).to exist
    end
  end

  it "audita el archivado con el antes y el después" do
    with_tenant(organization) do
      service = create(:service, company:)

      described_class.call(service:)

      event = events("service.archived").sole
      expect(event).to have_attributes(auditable_type: "Appointments::Service", auditable_id: service.id)
      expect(event.before).to eq("archived_at" => nil)
      expect(event.after.keys).to eq([ "archived_at" ])
    end
  end

  it "archivar dos veces es idempotente: no cambia archived_at ni duplica la auditoría" do
    with_tenant(organization) do
      service = create(:service, company:)
      first_time = Time.zone.local(2026, 11, 10, 15, 0, 0)
      travel_to(first_time) { described_class.call(service:) }

      travel_to(first_time + 1.day) { described_class.call(service: Appointments::Service.find(service.id)) }

      expect(Appointments::Service.find(service.id).archived_at).to eq(first_time)
      expect(events("service.archived").size).to eq(1)
    end
  end

  it "no toca los demás servicios de la empresa ni los de otra empresa" do
    with_tenant(organization) do
      target = create(:service, company:)
      sibling = create(:service, company:)
      foreign = create(:service, company: other_company)

      described_class.call(service: target)

      expect(Appointments::Service.where(archived_at: nil).pluck(:id)).to contain_exactly(sibling.id, foreign.id)
    end
  end
end
