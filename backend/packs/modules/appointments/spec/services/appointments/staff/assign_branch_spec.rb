require "rails_helper"

RSpec.describe Appointments::Staff::AssignBranch do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:other_company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "asigna la sucursal y lo audita", :aggregate_failures do
    with_tenant(organization) do
      assignment = described_class.call(professional:, branch_id: branch.id)

      expect(assignment).to be_persisted
      expect(assignment).to have_attributes(professional_id: professional.id, branch_id: branch.id, company_id: company.id)
      event = events("professional.assigned").sole
      expect(event.after).to include("professional_id" => professional.id, "branch_id" => branch.id)
    end
  end

  it "es idempotente: asignar de nuevo devuelve la misma asignación sin duplicar ni auditar otra vez", :aggregate_failures do
    with_tenant(organization) do
      first = described_class.call(professional:, branch_id: branch.id)
      again = described_class.call(professional:, branch_id: branch.id)

      expect(again.id).to eq(first.id)
      expect(Appointments::ProfessionalBranchAssignment.count).to eq(1)
      expect(events("professional.assigned").size).to eq(1)
    end
  end

  it "una sucursal de otra empresa lanza RecordInvalid (branch_id) y no deja nada", :aggregate_failures do
    with_tenant(organization) do
      foreign = create(:branch, company: other_company)

      expect { described_class.call(professional:, branch_id: foreign.id) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(Appointments::ProfessionalBranchAssignment.count).to eq(0)
      expect(events("professional.assigned")).to be_empty
    end
  end

  it "un profesional archivado no admite asignaciones nuevas" do
    with_tenant(organization) do
      archived = create(:professional, company:, archived_at: Time.current)

      expect { described_class.call(professional: archived, branch_id: branch.id) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
