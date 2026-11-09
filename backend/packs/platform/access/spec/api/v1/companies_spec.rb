require "swagger_helper"

RSpec.describe "API v1: empresas" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }

  path "/api/v1/organizations/{organization_id}/companies" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Lista las empresas que el usuario puede ver" do
      tags "Empresas"
      description "Solo las empresas donde el usuario tiene `platform.company.read` (org_owner y org_admin, todas; company_manager, la suya)."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      response "200", "las empresas visibles" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        schema type: :object, required: %w[data page], additionalProperties: false, properties: {
          data: { type: :array, items: { "$ref" => "#/components/schemas/Company" } },
          page: { "$ref" => "#/components/schemas/PageInfo" }
        }

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ world.company_a.id ]) }
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "organización suspendida (`access.organization_suspended`)" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        before { world.organization.update!(status: "suspended") }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.organization_suspended") }
      end

      response "404", "la organización no existe o el usuario no pertenece a ella" do
        let!(:signed_in) { sign_in(user_with_role("org_owner", build_access_world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de la empresa"

    get "Obtiene una empresa" do
      tags "Empresas"
      description "Exige `platform.company.read`. Una empresa fuera del alcance de los memberships del usuario responde 404."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la empresa" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:id) { world.company_a.id }
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/Company" } }, required: %w[data], additionalProperties: false

        run_test! { |response| expect(response.parsed_body.dig("data", "slug")).to eq(world.company_a.slug) }
      end

      response "401", "sin sesión válida" do
        let(:id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "visible por una sucursal, pero sin permiso sobre la empresa (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_custom_role(world, scope_level: "branch", branch: world.branch_a1)) }
        let(:id) { world.company_a.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "la empresa no existe o está fuera del alcance del usuario" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:id) { world.company_b.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end
end
