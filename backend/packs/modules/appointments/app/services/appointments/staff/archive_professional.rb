module Appointments
  module Staff
    # "Deleting" a professional: it is archived, never destroyed, so history keeps referencing it (with its assignments
    # and services). Idempotent: archiving an archived professional changes nothing and audits nothing.
    module ArchiveProfessional
      module_function

      def call(professional:)
        return professional if professional.archived?

        professional.archived_at = Time.current
        Catalog::SaveAudited.call(professional, action: "professional.archived", fields: %w[archived_at])
      end
    end
  end
end
