module Idempotency
  # Fila de idempotency_keys. Modelo PRIVADO del pack: lo usa Idempotency::Processor.
  class Key < ApplicationRecord
    self.table_name = "idempotency_keys"

    TTL = 24.hours

    # La respuesta guardada es del negocio (puede llevar datos personales): se cifra en la BD. No se busca por ella, así
    # que el cifrado es no determinista.
    encrypts :response_body

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    scope :expired, ->(now) { where(expires_at: ..now) }
  end
end
