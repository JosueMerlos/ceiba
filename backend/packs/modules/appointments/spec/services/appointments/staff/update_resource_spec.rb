require "rails_helper"

RSpec.describe Appointments::Staff::UpdateResource do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:resource) { create_in(organization, :resource, branch:, name: "Sala 1", kind: "room") }

  def events(action) = Audit::Event.where(action:).to_a

  it "cambia solo lo enviado y audita antes y después", :aggregate_failures do
    with_tenant(organization) do
      updated = described_class.call(resource:, attributes: { name: "Sala 2" })

      expect(updated.reload).to have_attributes(name: "Sala 2", kind: "room")
      event = events("resource.updated").sole
      expect([ event.before, event.after ]).to eq([ { "name" => "Sala 1" }, { "name" => "Sala 2" } ])
    end
  end

  it "no audita si nada cambió" do
    with_tenant(organization) do
      described_class.call(resource:, attributes: { name: "Sala 1" })

      expect(events("resource.updated")).to be_empty
    end
  end

  it "nunca mueve el recurso de sucursal ni de empresa ni lo desarchiva", :aggregate_failures do
    with_tenant(organization) do
      other = create(:branch, company:)

      described_class.call(resource:, attributes: { name: "Sala 1", branch_id: other.id, company_id: SecureRandom.uuid, archived_at: nil })

      expect(resource.reload).to have_attributes(branch_id: branch.id, company_id: company.id)
    end
  end

  it "un recurso archivado es historia de solo lectura (base: archived)", :aggregate_failures do
    with_tenant(organization) do
      archived = create(:resource, branch:, archived_at: Time.current, name: "Vieja")

      expect { described_class.call(resource: archived, attributes: { name: "Otra" }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(archived.reload.name).to eq("Vieja")
    end
  end

  it "un nombre en blanco lanza RecordInvalid y conserva el anterior" do
    with_tenant(organization) do
      expect { described_class.call(resource:, attributes: { name: " " }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(resource.reload.name).to eq("Sala 1")
    end
  end
end
