require "rails_helper"

RSpec.describe Customers::Update do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def events = Audit::Event.where(action: "customer.updated").to_a

  it "aplica los cambios, normaliza el teléfono y audita solo los nombres de los campos", :aggregate_failures do
    with_tenant(organization) do
      customer = create(:customer, company:, full_name: "Ana", phone_e164: "8888-7777")

      described_class.call(customer:, attributes: { full_name: "Ana María", phone_e164: "8888-6666", notes: "prefiere tardes" })

      expect(customer.reload.attributes.slice("full_name", "phone_e164", "notes")).to eq("full_name" => "Ana María", "phone_e164" => "+50588886666", "notes" => "prefiere tardes")
      expect(events.size).to eq(1)
      expect(events.first.metadata).to eq("changed" => %w[full_name phone_e164 notes])
      expect(events.first.attributes.slice("before", "after", "metadata").to_json).not_to match(/Ana|8888|6666|tardes/)
    end
  end

  it "sin cambios reales no audita" do
    with_tenant(organization) do
      customer = create(:customer, company:, full_name: "Ana")

      described_class.call(customer:, attributes: { full_name: "Ana" })

      expect(events).to be_empty
    end
  end

  it "con el teléfono de otro cliente de la empresa lanza RecordInvalid (phone_e164: taken) y no cambia nada", :aggregate_failures do
    with_tenant(organization) do
      create(:customer, company:, phone_e164: "8888-7777")
      customer = create(:customer, company:, full_name: "Ana", phone_e164: "8888-6666")

      expect { described_class.call(customer:, attributes: { full_name: "Nueva", phone_e164: "8888-7777" }) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:phone_e164).map(&:type)).to eq([ :taken ]) }
      expect(customer.reload.attributes.slice("full_name", "phone_e164")).to eq("full_name" => "Ana", "phone_e164" => "+50588886666")
      expect(events).to be_empty
    end
  end

  it "si la carrera la gana otro en el índice único, lanza RecordInvalid (phone_e164: taken) en vez de un error de base" do
    with_tenant(organization) do
      customer = create(:customer, company:, phone_e164: "8888-6666")
      allow(customer).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      expect { described_class.call(customer:, attributes: { phone_e164: "8888-7777" }) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:phone_e164).map(&:type)).to eq([ :taken ]) }
    end
  end

  it "ignora los atributos que no son editables (empresa y archivado)" do
    with_tenant(organization) do
      customer = create(:customer, company:)
      other = create_in(organization, :company)

      described_class.call(customer:, attributes: { company_id: other.id, archived_at: Time.current, full_name: "Ana" })

      expect(customer.reload.attributes.slice("company_id", "archived_at", "full_name")).to eq("company_id" => company.id, "archived_at" => nil, "full_name" => "Ana")
    end
  end

  it "un cliente archivado no se edita: lanza RecordInvalid (base: archived) y no cambia ni audita nada", :aggregate_failures do
    with_tenant(organization) do
      customer = create(:customer, company:, full_name: "Ana", archived_at: 1.day.ago)

      expect { described_class.call(customer:, attributes: { full_name: "Nueva" }) }
        .to raise_error(ActiveRecord::RecordInvalid) { |error| expect(error.record.errors.where(:base).map(&:type)).to eq([ :archived ]) }
      expect(customer.reload.full_name).to eq("Ana")
      expect(events).to be_empty
    end
  end
end
