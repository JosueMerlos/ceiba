require "swagger_helper"

# Creating a branch: the company comes from the ROUTE (never the body) and the permission is `platform.branch.create` asked at
# the company's scope, so a branch role is a 403 and a company outside the principal's reach is a 404.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: alta de sucursales" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let("Idempotency-Key") { SecureRandom.uuid }
  let(:body) { { name: "Sucursal Masaya", time_zone: "America/Managua", address: "Frente al parque", phone_e164: "+50588887777" } }

  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  def branches_of(company) = with_tenant(world.organization) { Tenancy::Directory.branches.where(company_id: company.id).order(:created_at).to_a }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Branch" } } }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Crea una sucursal en la empresa de la ruta" do
      tags "Sucursales"
      description "Exige `platform.branch.create` en la empresa de la ruta. Atributos: `name`, `time_zone` (IANA, obligatorios), `address` y `phone_e164`. " \
                  "La organización y la empresa salen de la ruta, nunca del cuerpo. La sucursal nace sin horario: queda cerrada hasta que se configure. " \
                  "Una zona horaria inválida u omitida responde 422 con el campo `time_zone`. Acepta `Idempotency-Key` (la misma clave con otro cuerpo responde 409 `idempotency.key_reused`)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/BranchInput" }

      response "201", "el company_manager crea la sucursal en su empresa" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("company_id" => world.company_a.id, "name" => "Sucursal Masaya", "time_zone" => "America/Managua",
                                                          "address" => "Frente al parque", "phone_e164" => "+50588887777", "status" => "active")
          expect(branches_of(world.company_a).map(&:name)).to include("Sucursal Masaya")
          expect(branches_of(world.company_a).last.id).to eq(response.parsed_body["data"]["id"])
          event = audit_events("branch.created").sole
          expect(event.auditable_id).to eq(response.parsed_body["data"]["id"])
          expect(event.after).to include("name" => "Sucursal Masaya", "time_zone" => "America/Managua", "company_id" => world.company_a.id)
        end
      end

      %w[org_owner org_admin].each do |role|
        response "201", "el #{role} crea la sucursal" do
          let!(:signed_in) { sign_in(user_with_role(role, world)) }
          schema single_schema

          run_test! { expect(branches_of(world.company_a).map(&:name)).to include("Sucursal Masaya") }
        end
      end

      response "201", "con organization_id y company_id en el cuerpo la sucursal igualmente cae en la empresa de la ruta" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:body) { super().merge(organization_id: SecureRandom.uuid, company_id: world.company_b.id) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]["company_id"]).to eq(world.company_a.id)
          expect(branches_of(world.company_b).map(&:name)).not_to include("Sucursal Masaya")
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} no puede crear sucursales y no se crea nada" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(branches_of(world.company_a).map(&:name)).not_to include("Sucursal Masaya")
          end
        end
      end

      response "404", "la empresa hermana (misma organización) a la que el company_manager no pertenece" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:company_id) { world.company_b.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(branches_of(world.company_b).map(&:name)).not_to include("Sucursal Masaya")
        end
      end

      response "404", "una empresa de otra organización" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:company_id) { build_access_world.company_a.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "422", "una zona horaria inválida: error en el campo time_zone y no se crea nada" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:body) { super().merge(time_zone: "Marte/Olympus") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "time_zone"))
          expect(branches_of(world.company_a).map(&:name)).not_to include("Sucursal Masaya")
        end
      end

      response "422", "sin time_zone (obligatoria): error en ese campo y no se crea nada" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:body) { super().except(:time_zone) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "time_zone"))
          expect(branches_of(world.company_a).map(&:name)).not_to include("Sucursal Masaya")
        end
      end

      response "409", "la misma `Idempotency-Key` con otro cuerpo (`idempotency.key_reused`)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let!(:first_creation) do
          post "/api/v1/organizations/#{organization_id}/companies/#{company_id}/branches", params: body.merge(name: "Otra"),
                                                                                              headers: { "X-CSRF-Token" => signed_in.csrf_token, "Idempotency-Key" => send("Idempotency-Key") }, as: :json
        end
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("idempotency.key_reused") }
      end

      response "400", "`Idempotency-Key` inválida (`idempotency.key_invalid`)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let("Idempotency-Key") { "" }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("idempotency.key_invalid") }
      end

      response "422", "sin nombre" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:body) { super().merge(name: " ") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "name")) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
