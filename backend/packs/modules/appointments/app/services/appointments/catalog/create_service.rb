module Appointments
  module Catalog
    # Creates a service in the company's catalog. The currency defaults to the company's and must match it.
    module CreateService
      module_function

      def call(company_id:, attributes:)
        service = Service.new(attributes.with_indifferent_access.slice(*Service::EDITABLE).merge(company_id:))
        SaveAudited.call(service, action: "service.created", fields: SERVICE_FIELDS)
      end
    end
  end
end
