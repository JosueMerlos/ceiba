module Events
  # The event as publishers and subscribers see it: immutable, without exposing the outbox row.
  Event = Data.define(:id, :name, :organization_id, :payload, :metadata, :occurred_at)
end
