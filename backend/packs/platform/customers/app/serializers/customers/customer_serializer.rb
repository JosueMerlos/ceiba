module Customers
  # Fields match components.schemas.Customer EXACTLY. phone_e164, email and notes are personal data: they only leave through
  # the customer endpoints, which require platform.customer.read.
  class CustomerSerializer < Api::Serializer
    attributes :id, :full_name, :phone_e164, :email, :notes, created_at: :iso8601, updated_at: :iso8601

    attribute(:archived_at) { |customer| customer.archived_at&.iso8601 }
  end
end
