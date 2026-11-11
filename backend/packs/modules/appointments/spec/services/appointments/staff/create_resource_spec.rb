require "rails_helper"

RSpec.describe Appointments::Staff::CreateResource do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "crea el recurso en la sucursal y lo audita con el después", :aggregate_failures do
    with_tenant(organization) do
      resource = described_class.call(company_id: company.id, branch_id: branch.id, attributes: { name: "  Sala 1 ", kind: "room" })

      expect(resource).to be_persisted
      expect(resource).to have_attributes(company_id: company.id, branch_id: branch.id, organization_id: organization.id, name: "Sala 1", kind: "room", active: true)
      event = events("resource.created").sole
      expect(event.before).to be_nil
      expect(event.after).to include("name" => "Sala 1", "kind" => "room")
    end
  end

  it "ignora lo que un cliente no puede escribir (company_id, branch_id, archived_at)", :aggregate_failures do
    with_tenant(organization) do
      other = create(:branch, company:)
      resource = described_class.call(company_id: company.id, branch_id: branch.id,
                                      attributes: { name: "Sillón", kind: "chair", branch_id: other.id, company_id: SecureRandom.uuid, archived_at: Time.current })

      expect(resource).to have_attributes(branch_id: branch.id, company_id: company.id, archived_at: nil)
    end
  end

  it "una sucursal de otra empresa lanza RecordInvalid y no crea nada", :aggregate_failures do
    with_tenant(organization) do
      foreign = create(:branch, company: create(:company))

      expect { described_class.call(company_id: company.id, branch_id: foreign.id, attributes: { name: "Sillón", kind: "chair" }) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Appointments::Resource.count).to eq(0)
      expect(events("resource.created")).to be_empty
    end
  end

  it "un tipo desconocido lanza RecordInvalid" do
    with_tenant(organization) do
      expect { described_class.call(company_id: company.id, branch_id: branch.id, attributes: { name: "Nave", kind: "spaceship" }) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
