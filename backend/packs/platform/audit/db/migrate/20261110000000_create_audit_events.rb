# audit_events: who did what, with before and after. TENANT table: each event belongs to an organization. APPEND-ONLY,
# guaranteed by a PostgreSQL trigger that rejects UPDATE, DELETE and TRUNCATE (the trigger ships in db/structure.sql; a
# REVOKE would not, because structure.sql is dumped without privileges).
#
# A control against the APPLICATION (and against raw SQL as app_user), not against a DBA: the table owner can disable
# the trigger.
#
# - `actor_type` / `actor_id`: the principal (user, api_key, platform_staff...) or `system` without id (jobs, seeds,
#   console).
# - `auditable_type` / `auditable_id`: the subject (polymorphic, no FK: an audit must neither block nor depend on its
#   subject's lifecycle).
# - `before` / `after`: ONLY the attributes that changed, without sensitive fields and with encrypted PII as [FILTERED].
# - No `updated_at`: a row never changes.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  REJECT_FUNCTION = <<~SQL.freeze
    CREATE FUNCTION reject_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION '% es append-only: % no está permitido', TG_TABLE_NAME, TG_OP USING ERRCODE = 'restrict_violation';
    END
    $$
  SQL

  def up
    safety_assured { execute REJECT_FUNCTION }

    create_tenant_table :audit_events do |t|
      t.string :actor_type, null: false
      t.uuid :actor_id
      t.string :request_id
      t.inet :ip
      t.string :user_agent
      t.string :action, null: false
      t.string :auditable_type, null: false
      t.uuid :auditable_id, null: false
      t.jsonb :before
      t.jsonb :after
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      # A subject's history ("what happened to this appointment") and the organization's chronological listing.
      t.index %i[organization_id auditable_type auditable_id], name: "idx_audit_events_subject"
      t.index %i[organization_id created_at], name: "idx_audit_events_created_at"
    end

    safety_assured do
      execute <<~SQL
        CREATE TRIGGER audit_events_append_only BEFORE UPDATE OR DELETE OR TRUNCATE ON audit_events
        FOR EACH STATEMENT EXECUTE FUNCTION reject_audit_mutation()
      SQL
    end
  end

  def down
    drop_table :audit_events
    safety_assured { execute "DROP FUNCTION reject_audit_mutation()" }
  end
end
