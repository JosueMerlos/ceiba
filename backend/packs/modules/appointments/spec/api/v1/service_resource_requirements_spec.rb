require "swagger_helper"

# The kinds of resource a service needs: one PUT replaces the whole set. A requirement is part of the company's catalog, so
# it needs the same permission as editing the service (`appointments.service.manage`, company_manager only).
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: recursos que necesita un servicio" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end
  let!(:service) { create_in(world.organization, :service, company: world.company_a) }
  let(:service_id) { service.id }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/ServiceResourceRequirements" } } }

  def kinds_of(id) = with_tenant(world.organization) { Appointments::ServiceResourceRequirement.where(service_id: id).pluck(:kind).sort }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{service_id}/resource_requirements" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :service_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del servicio"

    put "Reemplaza los tipos de recurso que necesita el servicio" do
      tags "Servicios"
      description "Exige `appointments.service.manage` en la empresa. Reemplaza el conjunto completo de `kinds` (`chair`, `room`, `equipment`): " \
                  "lo que no viene se quita y una lista vacía quita todo. El servicio debe ser de la empresa de la ruta."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ServiceResourceRequirementsInput" }

      let(:body) { { kinds: %w[room chair] } }

      response "200", "el conjunto queda fijado y auditado con el antes y el después" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { create_in(world.organization, :service_resource_requirement, service:, kind: "equipment") }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to eq("service_id" => service.id, "kinds" => %w[chair room])
          expect(kinds_of(service.id)).to eq(%w[chair room])
          expect(audit_events("service.resource_requirements_set").sole.before).to eq("kinds" => [ "equipment" ])
        end
      end

      response "200", "una lista vacía quita todos" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { create_in(world.organization, :service_resource_requirement, service:, kind: "chair") }
        let(:body) { { kinds: [] } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]["kinds"]).to eq([])
          expect(kinds_of(service.id)).to be_empty
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} no define los requisitos de un servicio" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(kinds_of(service.id)).to be_empty }
        end
      end

      response "404", "un servicio de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:service_id) { create_in(world.organization, :service, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "422", "un tipo desconocido no cambia nada" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { create_in(world.organization, :service_resource_requirement, service:, kind: "chair") }
        let(:body) { { kinds: %w[room spaceship] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "kinds", "code" => "invalid"))
          expect(kinds_of(service.id)).to eq([ "chair" ])
        end
      end

      response "422", "un tipo con byte NUL es inválido, no un 500" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kinds: [ "\u0000" ] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "kinds", "code" => "invalid"))
          expect(kinds_of(service.id)).to be_empty
        end
      end

      response "400", "más tipos que los que existen" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kinds: %w[chair room equipment chair] } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(kinds_of(service.id)).to be_empty }
      end

      response "400", "sin la lista o con elementos que no son texto" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kinds: [ 1 ] } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(kinds_of(service.id)).to be_empty }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
