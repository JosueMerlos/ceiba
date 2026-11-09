require "rails_helper"

# Esquema y garantía append-only de la auditoría (M0.11, ADR-0022).
#
#   audit_events       tabla TENANT: lo que ocurre dentro de una organización (negocio).
#   auth_audit_events  tabla GLOBAL: eventos de identidad (login, logout, revocación), que no tienen organización
#                      (users es global, ADR-0028). Ver docs/architecture/11-security.md.
#
# Ambas rechazan UPDATE, DELETE y TRUNCATE con un trigger de PostgreSQL: la garantía vive en la base, no en el código.
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

  # Criterio 1: SQL crudo como app_user (el rol con el que corre la aplicación y la suite).
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

      it "#{table}: ni siquiera el DUEÑO puede truncarla mientras el trigger exista" do
        OwnerConnection.rolled_back do |owner|
          expect { owner.execute("TRUNCATE #{table}") }.to raise_error(ActiveRecord::StatementInvalid, /append-only/)
        end
      end

      it "#{table}: el INSERT sí funciona (solo se puede añadir)" do
        expect(connection.select_value("SELECT count(*) FROM #{table}")).to be >= 1
      end
    end

    it "el dueño puede desactivar el trigger (control contra la APLICACIÓN, no contra un DBA): riesgo aceptado y documentado" do
      OwnerConnection.rolled_back do |owner|
        owner.execute("ALTER TABLE audit_events DISABLE TRIGGER USER")

        expect { owner.execute("UPDATE audit_events SET action = 'x'") }.not_to raise_error
      end
    end
  end
end
