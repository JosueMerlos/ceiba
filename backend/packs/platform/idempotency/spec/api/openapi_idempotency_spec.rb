require "rails_helper"

# El contrato (openapi/v1.yaml) documenta el header Idempotency-Key y sus errores como componentes reutilizables
# (M0.11, docs/architecture/07-api-contract.md#idempotencia): cada endpoint de creación idempotente los referencia con $ref
# en lugar de repetirlos. El archivo está al día respecto de los specs: lo comprueba infra/scripts/check-api-contract.sh.
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

    expect(responses.keys).to include("IdempotencyKeyReused", "IdempotencyKeyInvalid")
    expect(responses.dig("IdempotencyKeyReused", "content", "application/problem+json", "schema")).to eq("$ref" => "#/components/schemas/Problem")
    expect(responses.dig("IdempotencyKeyReused", "description")).to include("idempotency.key_reused")
  end
end
