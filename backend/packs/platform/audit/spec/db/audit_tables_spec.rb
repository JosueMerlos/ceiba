require "rails_helper"

# Schema and append-only guarantee of the audit trail.
#
#   audit_events       TENANT table: what happens inside an organization (business).
#   auth_audit_events  GLOBAL table: identity events (login, logout, revocation), which have no organization
#                      (users is global).
#
# Both reject UPDATE, DELETE and TRUNCATE with a PostgreSQL trigger: the guarantee lives in the database, not in code.
RSpec.describe "Tablas de auditoría" do
  let(:connection) { ApplicationRecord.connection }

  def index_on(table, columns) = connection.indexes(table).find { |index| index.columns == columns }

  describe "audit_events" do
    it "está registrada como tabla tenant" do
      expect(Database::TenantTables.names).to include("audit_events")
    end

    it "tiene las columnas del contrato" do
      expect(connection.columns(:audit_events).map(&:name)).to include(
        "id", "organization_id", "actor_type", "actor_id", "request_id", "ip", "user_agent", "action",
        "auditable_type", "auditable_id", "before", "after", "metadata", "created_at"
      )
    end

    it "before, after y metadata son jsonb; actor, acción y sujeto son obligatorios; no tiene updated_at" do
      columns = connection.columns(:audit_events).index_by(&:name)

      expect(columns.values_at("before", "after", "metadata").map(&:sql_type)).to eq(%w[jsonb jsonb jsonb])
      expect(columns.values_at("actor_type", "action", "auditable_type", "auditable_id", "created_at").map(&:null)).to eq([ false ] * 5)
      expect(columns).not_to have_key("updated_at")
    end

    it "indexa por (organización, tipo y id del sujeto) y por (organización, fecha)" do
      expect(index_on(:audit_events, %w[organization_id auditable_type auditable_id])).to be_present
      expect(index_on(:audit_events, %w[organization_id created_at])).to be_present
    end
  end

  describe "auth_audit_events" do
    it "NO es tenant (los eventos de identidad no tienen organización)" do
      expect(Database::TenantTables.names).not_to include("auth_audit_events")
      expect(connection.columns(:auth_audit_events).map(&:name)).not_to include("organization_id")
    end

    it "tiene las columnas del contrato" do
      expect(connection.columns(:auth_audit_events).map(&:name)).to include(
        "id", "action", "user_id", "request_id", "ip", "user_agent", "metadata", "created_at"
      )
    end

    it "la acción es obligatoria y el usuario admite NULL (login fallido con un correo sin cuenta)" do
      columns = connection.columns(:auth_audit_events).index_by(&:name)

      expect(columns["action"].null).to be(false)
      expect(columns["user_id"].null).to be(true)
    end

    it "indexa por usuario y fecha, y por fecha" do
      expect(index_on(:auth_audit_events, %w[user_id created_at])).to be_present
      expect(index_on(:auth_audit_events, %w[created_at])).to be_present
    end
  end

  # Raw SQL as app_user (the role the application and the suite run as).
  describe "append-only (criterio 1)" do
    let!(:organization) { create(:organization) }
    let(:event_id) { SecureRandom.uuid }

    before do
      connection.exec_insert(<<~SQL.squish, "seed", [ organization.id, event_id, SecureRandom.uuid ])
        INSERT INTO audit_events (id, organization_id, actor_type, action, auditable_type, auditable_id, created_at)
        VALUES ($2, $1, 'user', 'probe.created', 'Probe', $3, now())
      SQL
      connection.exec_insert("INSERT INTO auth_audit_events (id, action, created_at) VALUES ($1, 'auth.login_failed', now())", "seed", [ event_id ])
    end

    it "la conexión de la suite es app_user, no el dueño" do
      expect(connection.select_value("SELECT current_user")).to eq("app_user")
    end

    %w[audit_events auth_audit_events].each do |table|
      it "#{table}: un UPDATE por SQL crudo es rechazado por PostgreSQL" do
        expect { connection.execute("UPDATE #{table} SET action = 'manipulado'") }
          .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      end

      it "#{table}: un DELETE por SQL crudo es rechazado por PostgreSQL" do
        expect { connection.execute("DELETE FROM #{table}") }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      end

      it "#{table}: el rechazo vale aunque el UPDATE no alcance ninguna fila (trigger de sentencia)" do
        expect { connection.execute("UPDATE #{table} SET action = 'x' WHERE false") }
          .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      end

      it "#{table}: app_user no tiene TRUNCATE (privilegio ausente, no concedido)" do
        expect { connection.execute("TRUNCATE #{table}") }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
      end

      it "#{table}: el INSERT sí funciona (solo se puede añadir)" do
        expect(connection.select_value("SELECT count(*) FROM #{table}")).to be >= 1
      end
    end
  end

  # app_user is not the owner: it cannot dismantle the guarantee (regression guard against a privilege or ownership
  # change).
  describe "app_user no puede desmontar el trigger" do
    {
      "desactivar el trigger" => "ALTER TABLE audit_events DISABLE TRIGGER USER",
      "desactivar todos los triggers" => "ALTER TABLE auth_audit_events DISABLE TRIGGER ALL",
      "eliminar el trigger" => "DROP TRIGGER audit_events_append_only ON audit_events",
      "reemplazar la función" => "CREATE OR REPLACE FUNCTION reject_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL; END $$",
      "eliminar la función" => "DROP FUNCTION reject_audit_mutation() CASCADE",
      "eliminar la tabla" => "DROP TABLE audit_events",
      "reasignar el dueño" => "ALTER TABLE audit_events OWNER TO app_user",
      "cambiar session_replication_role" => "SET session_replication_role = replica"
    }.each do |name, sql|
      it "no puede #{name}" do
        expect { ApplicationRecord.connection.execute(sql) }.to raise_error(ActiveRecord::StatementInvalid, /must be owner|permission denied|superuser/i)
      end
    end

    it "app_user no es dueño de ninguna tabla de auditoría" do
      owners = ApplicationRecord.connection.select_values("SELECT tableowner FROM pg_tables WHERE tablename IN ('audit_events', 'auth_audit_events')")

      expect(owners).to eq(%w[app_owner app_owner])
    end
  end

  # Guard: the append-only tenant tables known to the isolation suite are EXACTLY those with the trigger.
  describe "guardián de TenantIsolation::APPEND_ONLY_TABLES" do
    let(:trigger_tables) do
      ApplicationRecord.connection.select_values(<<~SQL.squish)
        SELECT c.relname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_proc p ON p.oid = t.tgfoid
        WHERE p.proname = 'reject_audit_mutation' AND NOT t.tgisinternal ORDER BY c.relname
      SQL
    end

    it "toda tabla con el trigger append-only y organization_id está en APPEND_ONLY_TABLES, y viceversa" do
      tenant_with_trigger = trigger_tables & Database::TenantTables.names

      expect(tenant_with_trigger).to match_array(TenantIsolation::APPEND_ONLY_TABLES)
    end

    it "las dos tablas de auditoría llevan el trigger" do
      expect(trigger_tables).to eq(%w[audit_events auth_audit_events])
    end
  end

  # No seeded rows: the suite's connection (app_user) must not hold the table locked, or the owner's DDL from another
  # connection would wait forever for the suite's transaction to end.
  describe "el dueño de la tabla" do
    %w[audit_events auth_audit_events].each do |table|
      it "#{table}: ni siquiera el DUEÑO puede truncarla mientras el trigger exista" do
        OwnerConnection.rolled_back do |owner|
          expect { owner.execute("TRUNCATE #{table}") }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
        end
      end
    end

    it "puede desactivar el trigger (control contra la APLICACIÓN, no contra un DBA): riesgo aceptado y documentado" do
      OwnerConnection.rolled_back do |owner|
        owner.execute("ALTER TABLE audit_events DISABLE TRIGGER USER")

        expect { owner.execute("UPDATE audit_events SET action = 'x'") }.not_to raise_error
      end
    end
  end
end
