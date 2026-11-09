module Idempotency
  # Fila de idempotency_keys. Modelo PRIVADO del pack: lo usa Idempotency::Processor.
  class Key < ApplicationRecord
    self.table_name = "idempotency_keys"

    TTL = 24.hours

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :expired, ->(now) { where(expires_at: ..now) }
  end
end
