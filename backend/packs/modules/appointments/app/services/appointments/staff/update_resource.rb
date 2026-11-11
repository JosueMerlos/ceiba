module Appointments
  module Staff
    # Edits only the attributes sent. Never moves a resource to another branch or company: branch_id, company_id and
    # archived_at are not editable. An archived resource is read-only history (base: archived).
    module UpdateResource
      module_function

      def call(resource:, attributes:)
        if resource.archived?
          resource.errors.add(:base, :archived)
          raise ActiveRecord::RecordInvalid, resource
        end

        resource.assign_attributes(attributes.with_indifferent_access.slice(*Resource::EDITABLE))
        Catalog::SaveAudited.call(resource, action: "resource.updated", fields: RESOURCE_FIELDS, metadata: { branch_id: resource.branch_id })
      end
    end
  end
end
