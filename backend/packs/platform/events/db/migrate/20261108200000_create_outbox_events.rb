# outbox_events: the event is written in the SAME transaction as the use case.
#
# Tenant table: every event belongs to an organization and its subscriber runs in that context. The relay, which reads
# pending events of all organizations, is an explicit privileged path (Events::Relay, AllowedFiles of the
# Ceiba/TenantBypass cop) and will use the privileged role under RLS.
#
# `name` is the full versioned name (`platform.organization_provisioned.v1`): the version lives inside it, not in a
# separate column that could contradict it.
class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :outbox_events do |t|
      t.string :name, null: false
      t.jsonb :payload, null: false, default: {}
      # actor, request_id, company_id, branch_id
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :published_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps

      t.check_constraint "name ~ '^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*\\.v[0-9]+$'", name: "chk_outbox_events_name_format"
      # What the relay walks: pending events by id (UUIDv7: creation order). It shrinks as events are published.
      t.index :id, where: "published_at IS NULL", name: "idx_outbox_events_pending"
      t.index :published_at, where: "published_at IS NOT NULL", name: "idx_outbox_events_published_at"
    end
  end
end
