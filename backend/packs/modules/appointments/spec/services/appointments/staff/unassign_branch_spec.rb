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

  context "con horario semanal en esa sucursal" do
    def slot_ids = Appointments::WeeklySchedule.pluck(:id)

    it "borra las franjas del profesional en esa sucursal en la misma transacción y lo audita", :aggregate_failures do
      with_tenant(organization) do
        create(:professional_branch_assignment, professional:, branch:)
        own = [ 1, 2 ].map { create(:weekly_schedule, branch:, professional:, weekday: it) }

        described_class.call(professional:, branch_id: branch.id)

        expect(slot_ids).to be_empty
        expect(Appointments::ProfessionalBranchAssignment.where(professional_id: professional.id)).to be_empty
        event = events("professional.unassigned").sole
        expect(event.metadata).to include("schedule_slots_removed" => own.size)
      end
    end

    it "conserva las franjas del mismo profesional en otra sucursal, las de otros profesionales y las de la sucursal", :aggregate_failures do
      with_tenant(organization) do
        other_branch = create(:branch, company:)
        other_professional = create(:professional, company:)
        create(:professional_branch_assignment, professional:, branch:)
        create(:professional_branch_assignment, professional:, branch: other_branch)
        create(:professional_branch_assignment, professional: other_professional, branch:)
        kept = [ create(:weekly_schedule, branch: other_branch, professional:), create(:weekly_schedule, branch:, professional: other_professional), create(:weekly_schedule, branch:) ]
        create(:weekly_schedule, branch:, professional:, weekday: 3)

        described_class.call(professional:, branch_id: branch.id)

        expect(slot_ids).to match_array(kept.map(&:id))
      end
    end

    it "si algo falla la asignación y el horario siguen intactos (misma transacción)", :aggregate_failures do
      with_tenant(organization) do
        create(:professional_branch_assignment, professional:, branch:)
        create(:weekly_schedule, branch:, professional:)
        allow(Audit).to receive(:record).and_raise(ActiveRecord::StatementInvalid, "audit down")

        expect { described_class.call(professional:, branch_id: branch.id) }.to raise_error(ActiveRecord::StatementInvalid, "audit down")

        expect(slot_ids.size).to eq(1)
        expect(Appointments::ProfessionalBranchAssignment.where(professional_id: professional.id).count).to eq(1)
      end
    end
  end
end
