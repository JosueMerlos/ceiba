require "swagger_helper"

# Endpoint de ejemplo de M0.06 (criterio 1 y contrato). TEMPORAL: sin autenticación, solo en desarrollo y test.
# M0.07 añade la autenticación y M0.08 la autorización; entonces deja de existir el flag `open_organization_endpoint`.
RSpec.describe "API v1: organizaciones" do
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }

  path "/api/v1/organizations/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de la organización (UUIDv7)"

    get "Obtiene una organización" do
      tags "Organizaciones"
      description "Endpoint de ejemplo del contrato. Hoy sin autenticación y solo disponible en desarrollo; se protegerá en M0.07/M0.08."
      produces "application/json", "application/problem+json"

      response "200", "la organización" do
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/Organization" } }, required: %w[data], additionalProperties: false
        let(:id) { create(:organization, name: "Salón Ceiba", legal_name: nil).id }

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("id" => id, "name" => "Salón Ceiba", "legal_name" => nil, "country_code" => "NI", "status" => "active")
        end
      end

      response "404", "no existe (o el id no es un UUID)" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:id) { unknown_id }

        run_test! do |response|
          expect(response.media_type).to eq("application/problem+json")
          expect(response.parsed_body).to include("status" => 404, "code" => "resource.not_found", "instance" => "/api/v1/organizations/#{unknown_id}")
          expect(response.parsed_body.values_at("type", "title", "request_id")).to all(be_present)
        end
      end
    end
  end

  describe "formato y alcance" do
    it "devuelve las fechas en ISO 8601 UTC con Z" do
      organization = create(:organization)

      get "/api/v1/organizations/#{organization.id}"

      expect(response.parsed_body.dig("data", "created_at")).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z\z/)
    end

    it "responde 404 problem+json si el id no es un UUID" do
      get "/api/v1/organizations/no-es-un-uuid"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("resource.not_found")
    end

    it "no existe en producción mientras no haya autenticación (flag desactivado)" do
      organization = create(:organization)
      original = Rails.configuration.x.api.open_organization_endpoint
      Rails.configuration.x.api.open_organization_endpoint = false

      get "/api/v1/organizations/#{organization.id}"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("route.not_found")
    ensure
      Rails.configuration.x.api.open_organization_endpoint = original
    end

    it "viene desactivado por defecto fuera de desarrollo y test" do
      expect(File.read(Rails.root.join("config/environments/production.rb"))).not_to match(/open_organization_endpoint\s*=\s*true/)
    end
  end
end
