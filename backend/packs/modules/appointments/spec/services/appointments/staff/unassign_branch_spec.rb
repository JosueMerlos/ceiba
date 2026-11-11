require "rails_helper"

RSpec.describe Appointments::Staff::UnassignBranch do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }
  let(:branch) { create_in(organization, :branch, company:) }
  let(:professional) { create_in(organization, :professional, company:) }

  def events(action) = Audit::Event.where(action:).to_a

  it "quita la asignación de esa sucursal y lo audita", :aggregate_failures do
    with_tenant(organization) do
      assignment = create(:professional_branch_assignment, professional:, branch:)

      described_class.call(professional:, branch_id: branch.id)

      expect(Appointments::ProfessionalBranchAssignment.where(id: assignment.id)).to be_empty
      event = events("professional.unassigned").sole
      expect(event.before).to include("professional_id" => professional.id, "branch_id" => branch.id)
      expect(event.auditable_id).to eq(assignment.id)
    end
  end

  it "no toca las asignaciones a otras sucursales ni las de otros profesionales", :aggregate_failures do
    with_tenant(organization) do
      other_branch = create(:branch, company:)
      create(:professional_branch_assignment, professional:, branch:)
      kept_own = create(:professional_branch_assignment, professional:, branch: other_branch)
      kept_other = create(:professional_branch_assignment, professional: create(:professional, company:), branch:)

      described_class.call(professional:, branch_id: branch.id)

      expect(Appointments::ProfessionalBranchAssignment.pluck(:id)).to contain_exactly(kept_own.id, kept_other.id)
    end
  end

  it "sin asignación a esa sucursal lanza RecordNotFound y no audita", :aggregate_failures do
    with_tenant(organization) do
      expect { described_class.call(professional:, branch_id: branch.id) }.to raise_error(ActiveRecord::RecordNotFound)
      expect(events("professional.unassigned")).to be_empty
    end
  end
end
