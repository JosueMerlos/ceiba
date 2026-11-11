module Customers
  # Edits the contact data of a customer (never its company or archived state; those have their own operations).
  # An archived customer is read-only: editing it is a validation error (base: archived); restoring is the way back.
  module Update
    module_function

    def call(customer:, attributes:)
      if customer.archived?
        customer.errors.add(:base, :archived)
        raise ActiveRecord::RecordInvalid, customer
      end

      customer.assign_attributes(attributes.to_h.with_indifferent_access.slice(*Customer::EDITABLE))
      Persist.call(customer, action: "customer.updated")
    end
  end
end
