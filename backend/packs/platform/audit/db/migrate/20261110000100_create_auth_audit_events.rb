# auth_audit_events: eventos de identidad (login correcto o fallido, logout, revocación). Tabla GLOBAL, sin
# organization_id: `users` y `sessions` son globales (ADR-0028) y un login fallido con un correo sin cuenta no pertenece a
# ninguna organización. Meterlos en `audit_events` obligaría a un organization_id NULL, que rompe el guardián de tablas
# tenant (organization_id <=> política tenant_isolation), la FK a organizations y la RLS de M4.03.
#
# Mismo trigger append-only que audit_events. `user_id` NO lleva FK a propósito: la evidencia no debe impedir ni
# depender de la vida de la cuenta (anonimización de la Ley 787), y admite NULL (correo sin cuenta).
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
