module Appointments
  module Catalog
    # Brings an archived service back to the catalog, with the same id. `active` (a pause) is independent and is not touched.
    # Idempotent: restoring a current service changes nothing and audits nothing.
    module RestoreService
      module_function

      def call(service:)
        # The row is locked and re-read before deciding, so a concurrent archive and restore cannot both audit from a stale view.
        service.lock!
        return service unless service.archived?

        service.archived_at = nil
        SaveAudited.call(service, action: "service.restored", fields: %w[archived_at])
      end
    end
  end
end
