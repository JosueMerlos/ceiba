module Appointments
  module Staff
    # Creates a resource in a branch of the company. Only the editable attributes are taken: the company and the branch
    # come from the caller (the route), and a branch of another company is a validation error.
    module CreateResource
      module_function

      def call(company_id:, branch_id:, attributes:)
        resource = Resource.new(attributes.with_indifferent_access.slice(*Resource::EDITABLE).merge(company_id:, branch_id:))
        Catalog::SaveAudited.call(resource, action: "resource.created", fields: RESOURCE_FIELDS, metadata: { branch_id: })
      end
    end
  end
end
