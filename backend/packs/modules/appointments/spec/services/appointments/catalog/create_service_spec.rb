require "rails_helper"

RSpec.describe Appointments::Catalog::CreateService do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company, currency: "NIO") }
  let(:attributes) { { name: "Corte clásico", duration_minutes: 30, price_minor: 20_000 } }

  def events(action) = Audit::Event.where(action:).to_a

  it "crea el servicio con la moneda de la empresa y lo audita con el después", :aggregate_failures do
    with_tenant(organization) do
      service = described_class.call(company_id: company.id, attributes:)

      expect(service).to be_persisted
      expect(service).to have_attributes(company_id: company.id, name: "Corte clásico", currency: "NIO", price_minor: 20_000, buffer_before_minutes: 0, active: true)
      event = events("service.created").sole
      expect(event.before).to be_nil
      expect(event.after).to include("name" => "Corte clásico", "price_minor" => 20_000, "currency" => "NIO")
    end
  end

  it "una moneda distinta a la de la empresa lanza RecordInvalid (currency: mismatch) y no escribe ni audita nada" do
    with_tenant(organization) do
      expect { described_class.call(company_id: company.id, attributes: attributes.merge(currency: "USD")) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:currency).map(&:type)).to eq([ :mismatch ]) }

      expect([ Appointments::Service.count, events("service.created").size ]).to eq([ 0, 0 ])
    end
  end

  it "una empresa de otra organización no se resuelve: es un error de campo y no crea nada" do
    foreign_company = create_in(create(:organization), :company)

    with_tenant(organization) do
      expect { described_class.call(company_id: foreign_company.id, attributes:) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:company_id).map(&:type)).to eq([ :invalid ]) }
      expect(Appointments::Service.count).to eq(0)
    end
  end

  it "ignora atributos que no son del catálogo (organization_id, archived_at)" do
    with_tenant(organization) do
      service = described_class.call(company_id: company.id, attributes: attributes.merge(archived_at: Time.current, organization_id: SecureRandom.uuid))

      expect(service.archived_at).to be_nil
      expect(service.organization_id).to eq(organization.id)
    end
  end
end
