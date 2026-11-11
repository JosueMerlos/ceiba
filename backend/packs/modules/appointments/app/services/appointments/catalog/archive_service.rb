module Appointments
  module Catalog
    # "Deleting" a service: it is archived, never destroyed, so history keeps referencing it. Idempotent: archiving an
    # archived service changes nothing and audits nothing.
    module ArchiveService
      module_function

      def call(service:)
        return service if service.archived?

        service.archived_at = Time.current
        SaveAudited.call(service, action: "service.archived", fields: %w[archived_at])
      end
    end
  end
end
