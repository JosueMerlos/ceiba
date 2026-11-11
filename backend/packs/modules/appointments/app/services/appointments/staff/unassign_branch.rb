module Appointments
  module Staff
    # Removes a professional from a branch. Everything that hangs from the assignment goes in the same transaction (the
    # composite foreign keys leave no orphans). A professional that is not assigned there raises ActiveRecord::RecordNotFound.
    module UnassignBranch
      module_function

      def call(professional:, branch_id:)
        ApplicationRecord.transaction(requires_new: true) do
          assignment = ProfessionalBranchAssignment.find_by!(professional_id: professional.id, branch_id:)
          assignment.lock!
          assignment.destroy!
          Audit.record(action: "professional.unassigned", subject: assignment, before: assignment.attributes.slice("professional_id", "branch_id"))
          assignment
        end
      end
    end
  end
end
