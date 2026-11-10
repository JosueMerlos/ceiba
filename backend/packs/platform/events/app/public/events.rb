# A use case publishes an event in the SAME transaction as its data change; a relay delivers it after the commit:
#
#   ApplicationRecord.transaction do
#     appointment.save!
#     Events.publish("appointments.appointment_booked.v1", appointment_id: appointment.id, ...)
#   end
module Events
  # Inserts the event into the outbox, inside the current transaction and with the context's organization.
  #
  # - Validates the payload against the event's registered schema: no schema => Events::UnknownEvent; invalid payload =>
  #   Events::InvalidPayload. Nothing is written on failure.
  # - Outside a transaction it raises Events::NotInTransaction: there would be no atomicity with the data change.
  # - `metadata:` is merged with the context's (company and branch). Returns the published Events::Event.
  #
  # The payload is a hash (`publish(name, { id: 1 })`) or keyword arguments (`publish(name, id: 1)`).
  def self.publish(name, payload = nil, metadata: {}, **fields)
    Publisher.call(name:, payload: payload || fields, metadata:)
  end

  # Registers an event subscriber. `as:` is the subscriber name (unique per event) and the idempotency key in
  # processed_events. The handler (block or object responding to `call`) receives an Events::Event and runs INSIDE the
  # event's tenant context and a transaction; if it raises, nothing it did persists and Sidekiq retries.
  #
  # Registered from `config.to_prepare` (idempotent): the handler must be idempotent itself if it touches external
  # systems, because delivery is at-least-once.
  #
  #   Events.subscribe("platform.organization_provisioned.v1", as: "notifications.welcome", queue: "notifications") do |event|
  #     ...
  #   end
  def self.subscribe(event_name, as:, queue: Subscriptions::DEFAULT_QUEUE, handler: nil, &block)
    Subscriptions.register(event_name:, subscriber: as, handler: handler || block, queue:)
  end
end
