module Customers
  # Archives a customer: the row stays (its history belongs to the company) but it leaves the active listings.
  # Archiving an archived customer changes nothing.
  module Archive
    module_function

    def call(customer:)
      return customer if customer.archived?

      customer.archived_at = Time.current
      Persist.call(customer, action: "customer.archived")
    end
  end
end
