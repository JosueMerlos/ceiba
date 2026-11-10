require "rails_helper"

# Schema of idempotency_keys: TENANT table, one key per (organization, principal, key).
RSpec.describe "Tabla idempotency_keys" do
  let(:connection) { ApplicationRecord.connection }

  it "está registrada como tabla tenant" do
    expect(Database::TenantTables.names).to include("idempotency_keys")
  end

  it "tiene las columnas del contrato" do
    expect(connection.columns(:idempotency_keys).map(&:name)).to include(
      "id", "organization_id", "principal_key", "key", "request_fingerprint", "response_status", "response_body",
      "response_headers", "content_type", "expires_at", "created_at"
    )
  end

  it "organización, principal, clave, fingerprint y caducidad son obligatorios; la respuesta admite NULL (reserva en curso)" do
    columns = connection.columns(:idempotency_keys).index_by(&:name)

    expect(columns.values_at("principal_key", "key", "request_fingerprint", "expires_at").map(&:null)).to eq([ false ] * 4)
    expect(columns.values_at("response_status", "response_body").map(&:null)).to eq([ true, true ])
  end

  it "es única por (organización, principal, clave)" do
    index = connection.indexes(:idempotency_keys).find { |candidate| candidate.columns == %w[organization_id principal_key key] }

    expect(index&.unique).to be(true)
  end

  it "indexa la caducidad (purga de claves vencidas)" do
    expect(connection.indexes(:idempotency_keys).map(&:columns)).to include(%w[expires_at])
  end
end
