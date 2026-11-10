module Events
  class ProcessedEvent < ApplicationRecord
    self.table_name = "processed_events"

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :event_id, :subscriber, presence: true

    scope :older_than, ->(before) { where(processed_at: ...before) }
  end
end
