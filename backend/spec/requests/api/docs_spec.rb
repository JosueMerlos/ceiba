require "rails_helper"

# Swagger UI at /api/docs ONLY in development and staging.
RSpec.describe "Documentación de la API (/api/docs)" do
  it "sirve Swagger UI en test/desarrollo" do
    get "/api/docs/index.html"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("swagger-ui")
  end

  it "sirve el contrato versionado" do
    get "/api/docs/v1.yaml"

    expect(response).to have_http_status(:ok)
    # rswag-api re-serializes the YAML (another line wrap): the document is compared, not the text.
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
