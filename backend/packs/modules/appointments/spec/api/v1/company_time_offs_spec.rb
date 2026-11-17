require "swagger_helper"

# Absences of a professional seen from the COMPANY, for the ones a branch route cannot reach (a professional with no branch
# is a 404 there). Permissions are asked at the company's scope: only staff with `appointments.time_off.read` / `.manage` on
# the whole company pass, so a branch role and the person's own `manage_own` are 403 here.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: ausencias de un profesional por empresa" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  list_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/TimeOff" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }

  def professional_in(company, **attributes) = create_in(world.organization, :professional, company:, **attributes)
  def assign(professional, branch) = create_in(world.organization, :professional_branch_assignment, professional:, branch:)
  def time_off_for(owner, **attributes) = create_in(world.organization, :time_off, **owner, **attributes)
  def stored_time_offs = with_tenant(world.organization) { Appointments::TimeOff.order(:created_at).to_a }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  let!(:orphan) { professional_in(world.company_a, display_name: "Sin sucursal") }
  let(:professional_id) { orphan.id }
  let!(:mine) { time_off_for({ professional: orphan }, reason: "Vacaciones") }
  let!(:theirs) { time_off_for({ professional: professional_in(world.company_a, display_name: "Otra") }, reason: "Congreso") }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/professionals/{professional_id}/time_offs" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional de la empresa, con o sin sucursales"

    get "Lista las ausencias de un profesional desde la empresa" do
      tags "Ausencias"
      description "Exige `appointments.time_off.read` en el alcance de la EMPRESA (solo gerencia de empresa): un rol de sucursal o el propio profesional " \
                  "(`manage_own`) reciben 403. Alcanza a profesionales con y sin sucursales, por lo que permite revisar las ausencias de uno que quedó " \
                  "sin asignar. El profesional debe ser de la empresa de la ruta (si no, 404). Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      response "200", "las ausencias de un profesional sin sucursales, sin las de otros" do
        let!(:signed_in) { sign_in(manager) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ mine.id ])
          expect(response.parsed_body["data"].first).to include("professional_id" => orphan.id, "resource_id" => nil, "reason" => "Vacaciones")
        end
      end

      response "200", "también las de un profesional asignado a una sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let!(:assignment) { assign(orphan, world.branch_a1) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ mine.id ]) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el branch_manager no entra por la ruta de empresa aunque el profesional esté en su sucursal" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let!(:assignment) { assign(orphan, world.branch_a1) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "403", "el receptionist no lee" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el propio profesional (manage_own) no entra por esta ruta" do
        let(:person) { create(:user) }
        let!(:own) do
          user_with_role("professional", world, branch: world.branch_a1, user: person)
          professional_in(world.company_a, display_name: "Yo", user_id: person.id).tap { assign(it, world.branch_a1) }
        end
        let(:professional_id) { own.id }
        let!(:signed_in) { sign_in(person) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[org_owner org_admin].each do |role|
        response "403", "el #{role} no tiene claves de ausencias" do
          let!(:signed_in) { sign_in(user_with_role(role, world)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test!
        end
      end

      response "404", "un profesional de otra empresa de la misma organización" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/professionals/{professional_id}/time_offs/{professional_time_off_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_time_off_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de la ausencia del profesional de la ruta"

    let(:professional_time_off_id) { mine.id }

    delete "Borra una ausencia de un profesional desde la empresa" do
      tags "Ausencias"
      description "Exige `appointments.time_off.manage` en el alcance de la EMPRESA. La ausencia se busca SOLO entre las del profesional de la ruta. " \
                  "Borrado real, auditado por id sin el motivo."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "el company_manager borra la de un profesional sin sucursales, auditada sin el motivo" do
        let!(:signed_in) { sign_in(manager) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(stored_time_offs.map(&:id)).to eq([ theirs.id ])
          expect(audit_events("time_off.deleted").sole.attributes.slice("before", "after", "metadata").to_json).not_to include("Vacaciones")
        end
      end

      response "403", "el branch_manager no borra por la ruta de empresa y la fila sobrevive" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let!(:assignment) { assign(orphan, world.branch_a1) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} no borra" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(stored_time_offs.size).to eq(2) }
        end
      end

      %w[org_owner org_admin].each do |role|
        response "403", "el #{role} no borra" do
          let!(:signed_in) { sign_in(user_with_role(role, world)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(stored_time_offs.size).to eq(2) }
        end
      end

      response "404", "la ausencia de OTRO profesional por la URL de este: la fila sobrevive" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_time_off_id) { theirs.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
