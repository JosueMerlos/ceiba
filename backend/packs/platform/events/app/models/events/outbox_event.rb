module Events
  # Outbox row. Private to the pack: the rest of the app publishes with Events.publish and subscribes with
  # Events.subscribe, never touching the table.
  class OutboxEvent < ApplicationRecord
    self.table_name = "outbox_events"

    NAME_FORMAT = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.v[0-9]+\z/

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :name, format: { with: NAME_FORMAT }
    validates :occurred_at, presence: true

    scope :pending, -> { where(published_at: nil) }
    scope :published, -> { where.not(published_at: nil) }
    scope :in_publication_order, -> { order(:id) }
    scope :purgeable, ->(before) { published.where(published_at: ...before) }

    def to_event
      Event.new(id:, name:, organization_id:, payload:, metadata:, occurred_at:)
    end
  end
end
