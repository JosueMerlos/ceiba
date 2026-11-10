module Audit
  # Row of audit_events. Private to the pack; written via Audit.record. Insert-only: a PostgreSQL trigger rejects
  # UPDATE/DELETE/TRUNCATE and the model is read-only once saved.
  class Event < ApplicationRecord
    self.table_name = "audit_events"

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :actor_type, :action, :auditable_type, :auditable_id, presence: true

    def readonly? = persisted? || super
  end
end
