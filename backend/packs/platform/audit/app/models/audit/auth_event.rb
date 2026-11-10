module Audit
  # Row of auth_audit_events (global, no organization). Private to the pack; written via Audit.record_auth.
  class AuthEvent < ApplicationRecord
    self.table_name = "auth_audit_events"

    validates :action, presence: true

    def readonly? = persisted? || super
  end
end
