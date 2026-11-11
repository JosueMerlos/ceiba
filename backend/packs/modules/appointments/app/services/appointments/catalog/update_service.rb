module Appointments
  module Catalog
    # Edits only the attributes sent. Never moves a service to another company: company_id and archived_at are not editable.
    # An archived service is read-only history: editing it is a validation error (base: archived).
    module UpdateService
      module_function

      def call(service:, attributes:)
        if service.archived?
          service.errors.add(:base, :archived)
          raise ActiveRecord::RecordInvalid, service
        end

        service.assign_attributes(attributes.with_indifferent_access.slice(*Service::EDITABLE))
        SaveAudited.call(service, action: "service.updated", fields: SERVICE_FIELDS)
      end
    end
  end
end
