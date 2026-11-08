# API pública del pack platform/events (junto con Events::Event, Events::Schemas y los errores).
#
# Un caso de uso publica un evento en la MISMA transacción que su cambio de datos; un relay lo entrega después del
# commit (ADR-0009, docs/architecture/06-events-and-jobs.md):
#
#   ApplicationRecord.transaction do
#     appointment.save!
#     Events.publish("appointments.appointment_booked.v1", appointment_id: appointment.id, ...)
#   end
module Events
  # Inserta el evento en el outbox, dentro de la transacción en curso y con la organización del contexto.
  #
  # - Valida el payload contra el esquema registrado del evento: sin esquema => Events::UnknownEvent; payload que no lo
  #   cumple => Events::InvalidPayload. Nada se escribe si falla.
  # - Fuera de una transacción lanza Events::NotInTransaction: sin ella no habría atomicidad con el cambio de datos.
  # - `metadata:` se mezcla con la del contexto (empresa y sucursal). Devuelve el Events::Event publicado.
  def self.publish(name, payload = {}, metadata: {})
    Publisher.call(name:, payload:, metadata:)
  end

  # Registra un suscriptor de un evento. `as:` es el nombre del suscriptor (único por evento): es la clave de la
  # idempotencia en processed_events. El handler (bloque u objeto con `call`) recibe un Events::Event y corre DENTRO del
  # contexto de tenant del evento y de una transacción; si lanza, nada de lo que hizo queda y Sidekiq reintenta.
  #
  # Se registra desde `config.to_prepare` (idempotente): el handler debe ser idempotente por sí mismo si toca sistemas
  # externos, porque la entrega es al menos una vez.
  #
  #   Events.subscribe("platform.organization_provisioned.v1", as: "notifications.welcome", queue: "notifications") do |event|
  #     ...
  #   end
  def self.subscribe(event_name, as:, queue: Subscriptions::DEFAULT_QUEUE, handler: nil, &block)
    Subscriptions.register(event_name:, subscriber: as, handler: handler || block, queue:)
  end
end
