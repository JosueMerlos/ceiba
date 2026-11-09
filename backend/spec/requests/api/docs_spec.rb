require "rails_helper"

# Swagger UI en /api/docs SOLO en desarrollo y staging (docs/architecture/07-api-contract.md).
RSpec.describe "Documentación de la API (/api/docs)" do
  it "sirve Swagger UI en test/desarrollo" do
    get "/api/docs/index.html"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("swagger-ui")
  end

  it "sirve el contrato versionado" do
    get "/api/docs/v1.yaml"

    expect(response).to have_http_status(:ok)
    # rswag-api vuelve a serializar el YAML (otro ajuste de línea): se compara el documento, no el texto.
    expect(YAML.safe_load(response.body)).to eq(YAML.safe_load_file(Rails.root.join("openapi/v1.yaml")))
  end

  describe Api::Docs do
    it "está habilitada en desarrollo y test" do
      expect(described_class.enabled?(environment: "development", flag: nil)).to be(true)
      expect(described_class.enabled?(environment: "test", flag: nil)).to be(true)
    end

    it "NO está habilitada en producción salvo que staging la active explícitamente" do
      expect(described_class.enabled?(environment: "production", flag: nil)).to be(false)
      expect(described_class.enabled?(environment: "production", flag: "false")).to be(false)
      expect(described_class.enabled?(environment: "production", flag: "true")).to be(true)
    end
  end
end
