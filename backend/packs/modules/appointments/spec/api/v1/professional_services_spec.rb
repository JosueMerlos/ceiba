require "swagger_helper"

# The services a professional performs: one PUT replaces the whole set. A company record, so it needs
# `appointments.professional.manage` at the company.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: servicios que presta un profesional" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end
  let!(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:professional_id) { professional.id }
  let!(:corte) { create_in(world.organization, :service, company: world.company_a) }
  let!(:barba) { create_in(world.organization, :service, company: world.company_a) }
  let(:body) { { service_ids: [ corte.id, barba.id ] } }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Professional" } } }

  def linked_ids = with_tenant(world.organization) { Appointments::ProfessionalService.where(professional_id: professional.id).pluck(:service_id) }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/professionals/{professional_id}/services" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional"

    put "Fija los servicios que presta un profesional" do
      tags "Profesionales"
      description "Exige `appointments.professional.manage`. Reemplaza el conjunto completo: lo que no viene se quita y una lista vacía quita todos. " \
                  "Un servicio de otra empresa, inexistente o archivado (que aún no estaba vinculado) responde 422 y no cambia nada."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ProfessionalServicesInput" }

      response "200", "el conjunto queda como se envió y el profesional lo refleja" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]["service_ids"]).to contain_exactly(corte.id, barba.id)
          expect(linked_ids).to contain_exactly(corte.id, barba.id)
          expect(audit_events("professional.services_set").size).to eq(1)
        end
      end

      response "200", "reemplaza: lo que no viene se quita" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { create_in(world.organization, :professional_service, professional:, service: corte) }
        let(:body) { { service_ids: [ barba.id ] } }
        schema single_schema

        run_test! { expect(linked_ids).to eq([ barba.id ]) }
      end

      response "200", "una lista vacía quita todos" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { create_in(world.organization, :professional_service, professional:, service: corte) }
        let(:body) { { service_ids: [] } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]["service_ids"]).to eq([])
          expect(linked_ids).to be_empty
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} no define los servicios de un profesional" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(linked_ids).to be_empty
          end
        end
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { create_in(world.organization, :professional, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(linked_ids).to be_empty }
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(linked_ids).to be_empty }
      end

      response "422", "un servicio de otra empresa (`service_ids: invalid`): no se aplica ni el servicio válido" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { service_ids: [ corte.id, create_in(world.organization, :service, company: world.company_b).id ] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "service_ids", "code" => "invalid"))
          expect(linked_ids).to be_empty
        end
      end

      response "422", "un servicio archivado que no estaba vinculado (`service_id: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:old) { create_in(world.organization, :service, company: world.company_a, archived_at: Time.current) }
        let(:body) { { service_ids: [ old.id ] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { expect(linked_ids).to be_empty }
      end

      response "400", "service_ids debe ser una lista de textos" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { service_ids: [ 1, 2 ] } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(linked_ids).to be_empty }
      end

      response "400", "service_ids es obligatorio" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { {} }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
