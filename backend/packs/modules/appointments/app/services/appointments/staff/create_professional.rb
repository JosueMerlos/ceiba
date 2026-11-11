module Appointments
  module Staff
    # Creates a professional in the company. Only the editable attributes are taken: the company comes from the caller.
    module CreateProfessional
      module_function

      def call(company_id:, attributes:)
        professional = Professional.new(attributes.with_indifferent_access.slice(*Professional::EDITABLE).merge(company_id:))
        SaveAudited.call(professional, action: "professional.created", fields: PROFESSIONAL_FIELDS)
      end
    end
  end
end
