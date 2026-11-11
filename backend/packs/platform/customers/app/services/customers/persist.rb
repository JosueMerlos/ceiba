module Customers
  # Saves a customer and audits the change BY ID in the same savepoint: full_name is plaintext PII, so the event carries
  # the names of the fields that changed, never values.
  module Persist
    TRACKED_FIELDS = (Customer::EDITABLE + %w[archived_at]).freeze

    module_function

    def call(customer, action:)
      ApplicationRecord.transaction(requires_new: true) do
        customer.save!

        changed = customer.saved_changes.keys & TRACKED_FIELDS
        Audit.record(action:, subject: customer, metadata: { changed: }) if changed.any?
      end
      customer
    rescue ActiveRecord::RecordNotUnique
      # Lost a race on the unique index (raised after the savepoint rolled back): report it like the validation would have.
      customer.errors.add(:phone_e164, :taken)
      raise ActiveRecord::RecordInvalid, customer
    end
  end
end
