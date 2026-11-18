module Appointments
  # { customer id => full name } for the agenda listing, empty for a principal who may not see them. Must run inside a tenant context.
  module AgendaCustomerNames
    module_function

    def call(appointments:, principal:, branch:, company:)
      return {} unless AppointmentPolicy.new(principal, branch).customer_names?

      Customers::Lookup.full_names(ids: appointments.map(&:customer_id).uniq, company:)
    end
  end
end
