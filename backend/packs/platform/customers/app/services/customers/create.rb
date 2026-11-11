module Customers
  # Staff creation of a customer. Unlike FindOrCreate it does not hide an existing customer: an ACTIVE one with that phone
  # is a validation error (phone_e164: taken), while an ARCHIVED one is restored.
  module Create
    module_function

    def call(company_id:, attributes:)
      attributes = attributes.to_h.with_indifferent_access.slice(*Customer::EDITABLE)
      archived = Customer.where(company_id:).with_phone(attributes[:phone_e164]).first
      return Restore.call(archived, full_name: attributes[:full_name], email: attributes[:email], notes: attributes[:notes]) if archived&.archived?

      customer = Customer.new(attributes.merge(company_id:))
      Persist.call(customer, action: "customer.created")
    end
  end
end
