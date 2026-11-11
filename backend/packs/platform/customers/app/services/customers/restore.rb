module Customers
  # Brings an archived customer back (a person stays one customer per phone) with the data of the new request. Email and
  # notes are cleared unless sent: the number may now belong to someone else and must not inherit the previous holder's data.
  module Restore
    module_function

    def call(customer, full_name:, email: nil, notes: nil)
      customer.assign_attributes(archived_at: nil, full_name:, email: email.presence, notes: notes.presence)
      Persist.call(customer, action: "customer.restored")
    end
  end
end
