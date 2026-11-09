require "swagger_helper"

RSpec.describe "API v1: sucursales" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Lista las sucursales de una empresa que el usuario puede ver" do
      tags "Sucursales"
      description "Solo las sucursales donde el usuario tiene `platform.branch.read`: un company_manager ve todas las de su empresa; " \
                  "un branch_manager, la suya."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      response "200", "las sucursales visibles" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        schema type: :object, required: %w[data page], additionalProperties: false, properties: {
          data: { type: :array, items: { "$ref" => "#/components/schemas/Branch" } },
          page: { "$ref" => "#/components/schemas/PageInfo" }
        }

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to contain_exactly(world.branch_a1.id, world.branch_a2.id) }
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "la empresa está fuera del alcance del usuario" do
        let(:company_id) { world.company_b.id }
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de la sucursal"

    get "Obtiene una sucursal" do
      tags "Sucursales"
      description "Exige `platform.branch.read`. Una sucursal fuera del alcance del usuario (p. ej. la hermana de la suya) responde 404."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la sucursal" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let(:id) { world.branch_a1.id }
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/Branch" } }, required: %w[data], additionalProperties: false

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => id, "company_id" => world.company_a.id) }
      end

      response "401", "sin sesión válida" do
        let(:id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "visible pero sin permiso (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        let(:id) { world.branch_a1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "la sucursal no existe o está fuera del alcance del usuario" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let(:id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end
end
