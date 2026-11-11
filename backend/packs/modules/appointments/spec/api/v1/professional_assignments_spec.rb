require "swagger_helper"

# Assigning a professional to a branch. The permission is asked at the BRANCH of the route (`appointments.professional.assign`),
# so a branch_manager assigns to their branch and a sibling branch is a 404; the professional must belong to the route's company.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: asignación de profesionales a sucursales" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let(:branch_manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end
  let!(:professional) { create_in(world.organization, :professional, company: world.company_a) }
  let(:professional_id) { professional.id }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Professional" } } }

  def assign(professional, branch) = create_in(world.organization, :professional_branch_assignment, professional:, branch:)
  def branch_ids = with_tenant(world.organization) { Appointments::ProfessionalBranchAssignment.order(:created_at).pluck(:branch_id) }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/professionals/{professional_id}/assignment" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Sucursal a la que se asigna"
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional"

    put "Asigna un profesional a la sucursal" do
      tags "Profesionales"
      description "Exige `appointments.professional.assign` en la sucursal de la ruta. Idempotente: si ya está asignado responde 200 sin cambios. " \
                  "El profesional debe ser de la empresa de la ruta y no estar archivado; devuelve el profesional con sus `branch_ids`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "200", "el company_manager asigna a una sucursal de su empresa" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("id" => professional.id, "branch_ids" => [ world.branch_a1.id ])
          expect(branch_ids).to eq([ world.branch_a1.id ])
          expect(audit_events("professional.assigned").size).to eq(1)
        end
      end

      response "200", "el branch_manager asigna a SU sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema single_schema

        run_test! { expect(branch_ids).to eq([ world.branch_a1.id ]) }
      end

      response "200", "asignar de nuevo no duplica ni audita otra vez" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { assign(professional, world.branch_a1) }
        schema single_schema

        run_test! do
          expect(branch_ids).to eq([ world.branch_a1.id ])
          expect(audit_events("professional.assigned")).to be_empty
        end
      end

      response "200", "el branch_manager asigna a un profesional que ya trabaja en SU sucursal (sin cambios)" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { assign(professional, world.branch_a1) }
        schema single_schema

        run_test! { expect(branch_ids).to eq([ world.branch_a1.id ]) }
      end

      response "200", "el company_manager asigna a un profesional que solo trabaja en otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { assign(professional, world.branch_a2) }
        schema single_schema

        run_test! { expect(branch_ids).to contain_exactly(world.branch_a1.id, world.branch_a2.id) }
      end

      response "403", "el branch_manager no asigna a un profesional que solo trabaja en otra sucursal (exige alcance de empresa)" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { assign(professional, world.branch_a2) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(branch_ids).to eq([ world.branch_a2.id ])
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} no asigna" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(branch_ids).to be_empty
          end
        end
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to be_empty }
      end

      response "404", "una sucursal de otra empresa en la ruta: la base de datos nunca llega a verlo" do
        let!(:signed_in) { sign_in(manager) }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to be_empty }
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { create_in(world.organization, :professional, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to be_empty }
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to be_empty }
      end

      response "422", "un profesional archivado no admite asignaciones nuevas (`base: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:professional) { create_in(world.organization, :professional, company: world.company_a, archived_at: Time.current) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived"))
          expect(branch_ids).to be_empty
        end
      end
    end

    delete "Quita a un profesional de la sucursal" do
      tags "Profesionales"
      description "Exige `appointments.professional.assign` en la sucursal de la ruta. Sin asignación a esa sucursal responde 404."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      let!(:existing) { assign(professional, world.branch_a1) }

      response "204", "el company_manager quita la asignación; la de otra sucursal sigue" do
        let!(:signed_in) { sign_in(manager) }
        let!(:sibling) { assign(professional, world.branch_a2) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(branch_ids).to eq([ world.branch_a2.id ])
          expect(audit_events("professional.unassigned").map(&:auditable_id)).to eq([ existing.id ])
        end
      end

      response "204", "el branch_manager quita de SU sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }

        run_test! { expect(branch_ids).to be_empty }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el receptionist no quita asignaciones" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to eq([ world.branch_a1.id ]) }
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece: la asignación ahí sigue intacta" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:sibling) { assign(professional, world.branch_a2) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to contain_exactly(world.branch_a1.id, world.branch_a2.id) }
      end

      response "404", "el profesional no estaba asignado a esa sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to eq([ world.branch_a1.id ]) }
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { create_in(world.organization, :professional, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(branch_ids).to eq([ world.branch_a1.id ]) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
