# processed_events: subscriber idempotency. UNIQUE (event_id, subscriber) makes a second attempt to process the same
# event for the same subscriber fail in the database, not in an application check.
#
# No FK to outbox_events: both tables are purged independently (30 days each) and a processed_events row that outlives
# its event breaks nothing. The table is tenant: written inside the event's context.
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
