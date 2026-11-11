module Appointments
  module Staff
    # Assigns a professional to a branch of their company. Idempotent: an existing assignment is returned as is, with nothing
    # audited. Two concurrent first assignments race: the loser (the unique index) returns the winner's row.
    module AssignBranch
      module_function

      def call(professional:, branch_id:)
        find(professional, branch_id) || assign(professional, branch_id)
      rescue ActiveRecord::RecordNotUnique
        find(professional, branch_id)
      rescue ActiveRecord::RecordInvalid => error
        raise unless error.record.errors.of_kind?(:branch_id, :taken)

        find(professional, branch_id)
      end

      def find(professional, branch_id) = ProfessionalBranchAssignment.find_by(professional_id: professional.id, branch_id:)
      private_class_method :find

      def assign(professional, branch_id)
        assignment = ProfessionalBranchAssignment.new(professional_id: professional.id, branch_id:, company_id: professional.company_id)
        SaveAudited.call(assignment, action: "professional.assigned", fields: %w[professional_id branch_id])
      end
      private_class_method :assign
    end
  end
end
