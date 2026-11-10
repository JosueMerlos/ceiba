# auth_audit_events: identity events (successful or failed login, logout, revocation). GLOBAL table, no organization_id:
# `users` and `sessions` are global and a failed login with an unknown email belongs to no organization. Putting them in
# `audit_events` would force a NULL organization_id, which breaks the tenant-table guard (organization_id <=>
# tenant_isolation policy), the FK to organizations and RLS.
#
# Same append-only trigger as audit_events. `user_id` has NO FK on purpose: the evidence must neither block nor depend
# on the account's life (anonymization), and it admits NULL (email without an account).
class CreateAuthAuditEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :auth_audit_events, id: :uuid do |t|
      t.string :action, null: false
      t.uuid :user_id
      t.string :request_id
      t.inet :ip
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.index %i[user_id created_at], name: "idx_auth_audit_events_user"
      t.index :created_at, name: "idx_auth_audit_events_created_at"
    end

    safety_assured do
      execute <<~SQL
        CREATE TRIGGER auth_audit_events_append_only BEFORE UPDATE OR DELETE OR TRUNCATE ON auth_audit_events
        FOR EACH STATEMENT EXECUTE FUNCTION reject_audit_mutation()
      SQL
    end
  end

  def down
    drop_table :auth_audit_events
  end
end
