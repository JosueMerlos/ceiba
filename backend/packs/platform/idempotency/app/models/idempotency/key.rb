module Idempotency
  class Key < ApplicationRecord
    self.table_name = "idempotency_keys"

    TTL = 24.hours

    # The stored response is business data (it may hold personal data): encrypted in the DB. It is never searched by, so
    # the encryption is non-deterministic.
    encrypts :response_body

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :expired, ->(now) { where(expires_at: ..now) }
  end
end
