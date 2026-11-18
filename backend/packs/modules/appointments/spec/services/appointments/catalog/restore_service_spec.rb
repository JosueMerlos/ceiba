require "rails_helper"

RSpec.describe Appointments::Catalog::RestoreService do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def events(action) = Audit::Event.where(action:).to_a

  it "limpia archived_at, conserva el id y devuelve el servicio al catálogo" do
    with_tenant(organization) do
      service = create(:service, company:, archived_at: Time.zone.local(2026, 1, 1))

      described_class.call(service:)

      expect(Appointments::Service.find(service.id).archived_at).to be_nil
      expect(Appointments::Service.where(company_id: company.id).unarchived.pluck(:id)).to eq([ service.id ])
    end
  end

  it "audita la restauración con el antes y el después" do
    with_tenant(organization) do
      service = create(:service, company:, archived_at: Time.zone.local(2026, 1, 1))

      described_class.call(service:)

      event = events("service.restored").sole
      expect(event).to have_attributes(auditable_type: "Appointments::Service", auditable_id: service.id)
      expect(event.before).to eq("archived_at" => "2026-01-01T00:00:00.000Z")
      expect(event.after.keys).to eq([ "archived_at" ])
    end
  end

  it "restaurar uno vigente no audita nada" do
    with_tenant(organization) do
      service = create(:service, company:)

      described_class.call(service:)

      expect(events("service.restored")).to be_empty
    end
  end

  it "decide con la fila bloqueada: un restore sobre una copia desactualizada no repite la auditoría de otro restore" do
    with_tenant(organization) do
      service = create(:service, company:, archived_at: Time.zone.local(2026, 1, 1))
      stale = Appointments::Service.find(service.id)
      described_class.call(service:)

      described_class.call(service: stale)

      expect(events("service.restored").size).to eq(1)
    end
  end

  it "no mantiene el servicio activo/pausado: active no cambia al restaurar" do
    with_tenant(organization) do
      service = create(:service, company:, active: false, archived_at: Time.zone.local(2026, 1, 1))

      described_class.call(service:)

      expect(Appointments::Service.find(service.id)).to have_attributes(active: false, archived_at: nil)
    end
  end
end
