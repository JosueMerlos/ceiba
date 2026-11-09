module Audit
  # Fila de auth_audit_events (global, sin organización). Modelo PRIVADO del pack: se escribe con Audit.record_auth.
  class AuthEvent < ApplicationRecord
    self.table_name = "auth_audit_events"

    validates :action, presence: true

    def readonly? = persisted? || super
  end
end
