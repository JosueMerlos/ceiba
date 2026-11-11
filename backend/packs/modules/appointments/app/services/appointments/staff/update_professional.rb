module Appointments
  module Staff
    # Edits only the attributes sent. Never moves a professional to another company: company_id and archived_at are not
    # editable. An archived professional is read-only history: editing it is a validation error (base: archived).
    module UpdateProfessional
      module_function

      def call(professional:, attributes:)
        Staff.reject_archived!(professional)
        professional.assign_attributes(attributes.with_indifferent_access.slice(*Professional::EDITABLE))
        SaveAudited.call(professional, action: "professional.updated", fields: PROFESSIONAL_FIELDS)
      end
    end
  end
end
