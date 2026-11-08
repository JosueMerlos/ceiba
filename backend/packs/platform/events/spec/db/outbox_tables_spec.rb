require "rails_helper"

# Esquema del outbox (M0.10). outbox_events y processed_events son tablas TENANT (organization_id, política
# tenant_isolation, FK a organizations): un evento siempre pertenece a una organización y el suscriptor corre en su
# contexto. El relay (que sí cruza organizaciones) es un camino privilegiado explícito: ver docs/architecture/06.
RSpec.describe "Tablas del outbox" do
  let(:connection) { ApplicationRecord.connection }

  def index_on(table, columns)
    connection.indexes(table).find { |index| index.columns == columns }
  end

  it "outbox_events y processed_events están registradas como tablas tenant" do
    expect(Database::TenantTables.names).to include("outbox_events", "processed_events")
  end

  describe "outbox_events" do
    it "tiene las columnas del contrato" do
      expect(connection.columns(:outbox_events).map(&:name)).to include(
        "id", "organization_id", "name", "payload", "metadata", "occurred_at", "published_at", "attempts", "last_error"
      )
    end

    it "payload y metadata son jsonb NOT NULL; occurred_at es NOT NULL; published_at admite NULL" do
      columns = connection.columns(:outbox_events).index_by(&:name)

      expect(columns.values_at("payload", "metadata").map(&:sql_type)).to eq(%w[jsonb jsonb])
      expect(columns.values_at("payload", "metadata", "occurred_at", "name").map(&:null)).to eq([ false ] * 4)
      expect(columns["published_at"].null).to be(true)
    end

    it "tiene un índice parcial de pendientes por id (lo que recorre el relay)" do
      index = index_on(:outbox_events, [ "id" ])

      expect(index&.where).to match(/published_at IS NULL/)
    end

    it "tiene un índice parcial de publicados por published_at (purga)" do
      index = index_on(:outbox_events, [ "published_at" ])

      expect(index&.where).to match(/published_at IS NOT NULL/)
    end

    it "rechaza en la base un nombre de evento mal formado" do
      organization = new_organization

      expect do
        savepoint { connection.execute(<<~SQL) }
          INSERT INTO outbox_events (organization_id, name, occurred_at, created_at, updated_at)
          VALUES ('#{organization.id}', 'no es un evento', now(), now(), now())
        SQL
      end.to raise_error(ActiveRecord::StatementInvalid, /chk_outbox_events_name_format/)
    end
  end

  describe "processed_events" do
    it "tiene event_id, subscriber y processed_at NOT NULL" do
      columns = connection.columns(:processed_events).index_by(&:name)

      expect(columns.values_at("event_id", "subscriber", "processed_at").map(&:null)).to eq([ false ] * 3)
    end

    it "tiene UNIQUE (event_id, subscriber): la clave de la idempotencia" do
      index = index_on(:processed_events, %w[event_id subscriber])

      expect(index&.unique).to be(true)
    end

    it "tiene un índice por processed_at (purga)" do
      expect(index_on(:processed_events, [ "processed_at" ])).to be_present
    end
  end
end
