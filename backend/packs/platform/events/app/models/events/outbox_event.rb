module Events
  # Fila del outbox. Modelo PRIVADO del pack: el resto de la aplicación publica con Events.publish y se suscribe con
  # Events.subscribe, nunca toca la tabla.
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
  end
end
