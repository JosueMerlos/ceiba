# processed_events: la idempotencia de los suscriptores. El UNIQUE (event_id, subscriber) hace que el segundo intento
# de procesar el mismo evento para el mismo suscriptor falle en la base, no en una comprobación de la aplicación.
#
# Sin FK a outbox_events: la purga de ambas tablas es independiente (30 días cada una) y un processed_events que
# sobrevive a su evento no rompe nada. La tabla es tenant: se escribe dentro del contexto del evento.
class CreateProcessedEvents < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :processed_events do |t|
      t.uuid :event_id, null: false
      t.string :subscriber, null: false
      t.datetime :processed_at, null: false, default: -> { "now()" }
      t.timestamps

      t.index %i[event_id subscriber], unique: true, name: "uq_processed_events_event_subscriber"
      t.index :processed_at, name: "idx_processed_events_processed_at"
    end
  end
end
