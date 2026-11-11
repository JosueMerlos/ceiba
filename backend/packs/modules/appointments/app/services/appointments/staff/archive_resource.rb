module Appointments
  module Staff
    # "Deleting" a resource: it is archived, never destroyed, so history keeps referencing it (with its hours and absences).
    # Idempotent: archiving an archived resource changes nothing and audits nothing.
    module ArchiveResource
      module_function

      def call(resource:)
        return resource if resource.archived?

        resource.archived_at = Time.current
        SaveAudited.call(resource, action: "resource.archived", fields: %w[archived_at], metadata: { branch_id: resource.branch_id })
      end
    end
  end
end
