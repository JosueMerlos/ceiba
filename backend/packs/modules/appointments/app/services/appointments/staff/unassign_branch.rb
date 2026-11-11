module Appointments
  module Staff
    # Removes a professional from a branch. Everything that hangs from the assignment (their weekly hours in that branch) goes
    # in the same transaction: the composite foreign keys leave no orphans, and hours without the assignment mean nothing.
    # A professional that is not assigned there raises ActiveRecord::RecordNotFound.
    module UnassignBranch
      module_function

      def call(professional:, branch_id:)
        Staff.reject_archived!(professional)
        ApplicationRecord.transaction(requires_new: true) do
          assignment = ProfessionalBranchAssignment.find_by!(professional_id: professional.id, branch_id:)
          assignment.lock!
          removed = WeeklySchedule.where(professional_id: professional.id, branch_id:).delete_all
          assignment.destroy!
          Audit.record(action: "professional.unassigned", subject: assignment, before: assignment.attributes.slice("professional_id", "branch_id"),
                       metadata: { schedule_slots_removed: removed })
          assignment
        end
      end
    end
  end
end
