# audit_events: quién hizo qué, con el antes y el después (ADR-0022). Tabla TENANT: cada evento pertenece a una
# organización. APPEND-ONLY garantizado por un trigger de PostgreSQL que rechaza UPDATE, DELETE y TRUNCATE
# (el trigger viaja en db/structure.sql; un REVOKE no lo haría porque structure.sql se vuelca sin privilegios).
#
# Es un control contra la APLICACIÓN (y contra SQL crudo con el rol app_user), no contra un DBA: el dueño de la tabla
# puede desactivar el trigger (docs/architecture/11-security.md).
#
# - `actor_type` / `actor_id`: el principal (user, api_key, platform_staff...) o `system` sin id (jobs, seeds, consola).
# - `auditable_type` / `auditable_id`: el sujeto (polimórfico, sin FK: una auditoría no debe impedir ni depender del
#   ciclo de vida de su sujeto).
# - `before` / `after`: SOLO los atributos que cambiaron, sin campos sensibles y con la PII cifrada como [FILTERED].
# - Sin `updated_at`: una fila nunca cambia.
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

      # Historial de un sujeto ("qué le pasó a esta cita") y listado cronológico de la organización.
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
