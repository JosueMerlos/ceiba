require "swagger_helper"

# Contrato de las organizaciones del usuario (M0.08). Cada `response` ejecuta la petición real y valida el cuerpo.
RSpec.describe "API v1: organizaciones" do
  let(:world) { build_access_world }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }

  path "/api/v1/organizations" do
    get "Lista las organizaciones del usuario" do
      tags "Organizaciones"
      description "Las organizaciones donde el usuario autenticado tiene algún membership (selector de contexto, ADR-0028). " \
                  "Incluye las suspendidas, con su `status`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false, description: "Cursor opaco de la página anterior"

      response "200", "las organizaciones del usuario" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema type: :object, required: %w[data page], additionalProperties: false, properties: {
          data: { type: :array, items: { "$ref" => "#/components/schemas/Organization" } },
          page: { "$ref" => "#/components/schemas/PageInfo" }
        }

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ world.organization.id ]) }
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end
    end
  end

  path "/api/v1/organizations/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de la organización (UUIDv7)"

    get "Obtiene una organización" do
      tags "Organizaciones"
      description "Exige el permiso `platform.organization.read` (org_owner y org_admin). Una organización donde el usuario no tiene " \
                  "membership responde 404, igual que una inexistente."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la organización" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        let(:id) { world.organization.id }
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/Organization" } }, required: %w[data], additionalProperties: false

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("id" => id, "country_code" => "NI", "status" => "active")
        end
      end

      response "401", "sin sesión válida" do
        let(:id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "miembro de la organización sin el permiso, o la organización está suspendida (`access.forbidden`, `access.organization_suspended`)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:id) { world.organization.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "no existe, no es un UUID o el usuario no pertenece a ella" do
        let!(:signed_in) { sign_in(user_with_role("org_owner", build_access_world)) }
        let(:id) { world.organization.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.media_type).to eq("application/problem+json")
          expect(response.parsed_body).to include("status" => 404, "code" => "resource.not_found", "instance" => "/api/v1/organizations/#{id}")
        end
      end
    end
  end

  describe "formato" do
    before { sign_in(user_with_role("org_admin", world)) }

    it "devuelve las fechas en ISO 8601 UTC con Z" do
      get "/api/v1/organizations/#{world.organization.id}"

      expect(response.parsed_body.dig("data", "created_at")).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z\z/)
    end

    it "responde 404 problem+json si el id no es un UUID" do
      get "/api/v1/organizations/no-es-un-uuid"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["code"]).to eq("resource.not_found")
    end

    it "el flag temporal open_organization_endpoint ya no existe" do
      expect(Rails.root.glob("config/environments/*.rb").map(&:read).join).not_to include("open_organization_endpoint")
    end
  end
end
