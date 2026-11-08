module Events
  # Fila del outbox. Modelo PRIVADO del pack: el resto de la aplicación publica con Events.publish y se suscribe con
  # Events.subscribe, nunca toca la tabla.
  class OutboxEvent < ApplicationRecord
    self.table_name = "outbox_events"

    NAME_FORMAT = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.v[0-9]+\z/

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :name, format: { with: NAME_FORMAT }
    validates :occurred_at, presence: true

    # Optimización de latencia: tras el commit que confirma el evento se lanza el relay sin esperar al cron (5 s). Es
    # solo una optimización: si Redis falla el evento ya está confirmado y el cron lo publicará.
    after_commit :kick_relay, on: :create

    scope :pending, -> { where(published_at: nil) }
    scope :published, -> { where.not(published_at: nil) }
    scope :in_publication_order, -> { order(:id) }
    scope :purgeable, ->(before) { published.where(published_at: ...before) }

    def to_event
      Event.new(id:, name:, organization_id:, payload:, metadata:, occurred_at:)
    end

    private

    def kick_relay
      RelayJob.perform_async
    rescue StandardError => error
      Rails.logger.warn("events.kick_relay no pudo encolar el relay (el cron lo cubre): #{error.class}: #{error.message}")
    end
  end
end
