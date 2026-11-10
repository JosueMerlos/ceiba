require "rails_helper"

# The contract (openapi/v1.yaml) documents the Idempotency-Key header and its errors as reusable components: each
# idempotent creation endpoint references them with $ref instead of repeating them. The file is kept in sync with the
# specs by a CI check.
RSpec.describe "Contrato OpenAPI: Idempotency-Key" do
  let(:document) { YAML.safe_load_file(Rails.root.join("openapi/v1.yaml")) }
  let(:parameter) { document.dig("components", "parameters", "IdempotencyKey") }

  it "define el parámetro de cabecera IdempotencyKey" do
    expect(parameter).to include("name" => "Idempotency-Key", "in" => "header", "required" => false)
  end

  it "su esquema coincide con la validación real: ASCII imprimible, 1 a 255 caracteres" do
    schema = parameter.fetch("schema")

    expect(schema).to include("type" => "string", "minLength" => 1, "maxLength" => 255)
    expect(Idempotency::Processor::VALID_KEY).to match(%w[! ~ a].join)
    expect(schema["pattern"]).to eq("^[!-~]+$")
  end

  it "define la variante obligatoria para los endpoints con `required: true`" do
    expect(document.dig("components", "parameters", "IdempotencyKeyRequired")).to include("name" => "Idempotency-Key", "required" => true)
  end

  it "define las respuestas 409 idempotency.key_reused y 400 idempotency.key_invalid / key_required como Problem" do
    responses = document.dig("components", "responses")

    expect(responses.keys).to include("IdempotencyKeyReused", "IdempotencyKeyInvalid", "IdempotencyRequestInProgress")
    expect(responses.dig("IdempotencyKeyReused", "content", "application/problem+json", "schema")).to eq("$ref" => "#/components/schemas/Problem")
    expect(responses.dig("IdempotencyKeyReused", "description")).to include("idempotency.key_reused")
  end

  it "documenta 409 idempotency.request_in_progress (la primera petición sigue en curso)" do
    response = document.dig("components", "responses", "IdempotencyRequestInProgress")

    expect(response["description"]).to include("idempotency.request_in_progress")
    expect(response.dig("content", "application/problem+json", "schema")).to eq("$ref" => "#/components/schemas/Problem")
  end

  it "documenta la cabecera de respuesta Idempotency-Replayed como componente reutilizable" do
    header = document.dig("components", "headers", "IdempotencyReplayed")

    expect(header).to include("schema" => a_hash_including("type" => "string", "enum" => [ "true" ]))
    expect(header["description"]).to include("repetida")
  end
end
