require "rails_helper"

RSpec.describe Appointments::Catalog::UpdateService do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company, currency: "NIO") }

  def events(action) = Audit::Event.where(action:).to_a

  it "cambia solo lo enviado y audita el antes y el después de lo que cambió" do
    with_tenant(organization) do
      service = create(:service, company:, name: "Corte", price_minor: 20_000, duration_minutes: 30)

      described_class.call(service:, attributes: { price_minor: 25_000 })

      expect(service.reload).to have_attributes(name: "Corte", price_minor: 25_000, duration_minutes: 30)
      event = events("service.updated").sole
      expect([ event.before, event.after ]).to eq([ { "price_minor" => 20_000 }, { "price_minor" => 25_000 } ])
    end
  end

  it "sin cambios reales no audita" do
    with_tenant(organization) do
      service = create(:service, company:, name: "Corte")

      described_class.call(service:, attributes: { name: "Corte" })

      expect(events("service.updated")).to be_empty
    end
  end

  it "una moneda distinta a la de la empresa lanza RecordInvalid y deja el servicio intacto" do
    with_tenant(organization) do
      service = create(:service, company:)

      expect { described_class.call(service:, attributes: { currency: "USD" }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(service.reload.currency).to eq("NIO")
      expect(events("service.updated")).to be_empty
    end
  end

  it "no deja cambiar la empresa ni la organización del servicio (adversarial)" do
    with_tenant(organization) do
      other_company = create(:company)
      service = create(:service, company:)

      described_class.call(service:, attributes: { company_id: other_company.id, organization_id: SecureRandom.uuid, name: "Nuevo" })

      expect(service.reload).to have_attributes(company_id: company.id, organization_id: organization.id, name: "Nuevo")
    end
  end

  it "un servicio archivado lanza RecordInvalid (base: archived) y no cambia ni audita", :aggregate_failures do
    with_tenant(organization) do
      service = create(:service, company:, price_minor: 20_000, archived_at: Time.current)

      expect { described_class.call(service:, attributes: { price_minor: 99 }) }.to raise_error(ActiveRecord::RecordInvalid) { |error|
        expect(error.record.errors.where(:base).map(&:type)).to eq([ :archived ])
      }
      expect(service.reload.price_minor).to eq(20_000)
      expect(events("service.updated")).to be_empty
    end
  end
end
