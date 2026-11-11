require "swagger_helper"

# Absences of a professional or a resource, under a BRANCH route. The owner is searched among the ones that belong to that
# branch (an assigned professional, the branch's resource) and the absence ONLY among that owner's: another owner's id is a
# 404, never a deletion through somebody else's URL. Permissions are asked at the branch: staff with `appointments.time_off.manage`
# act on the branch's owners; a professional manages their OWN absences with `appointments.time_off.manage_own` (the record is
# linked to their user and assigned to the route's branch).
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: ausencias" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let(:branch_manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let(:absence) { { starts_at: "2026-11-16T09:00:00Z", ends_at: "2026-11-16T13:00:00Z", reason: "Congreso" } }
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
  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/TimeOff" } } }

  def professional_in(company, **attributes) = create_in(world.organization, :professional, company:, **attributes)
  def assign(professional, branch) = create_in(world.organization, :professional_branch_assignment, professional:, branch:)
  def time_off_for(owner, **attributes) = create_in(world.organization, :time_off, **owner, **attributes)
  def stored_time_offs = with_tenant(world.organization) { Appointments::TimeOff.order(:created_at).to_a }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/professionals/{professional_id}/time_offs" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional, asignado a la sucursal de la ruta"

    let(:person) { create(:user) }
    # The person linked to the professional record (a member of the branch, as the link requires); none by default.
    let(:own_user) { nil }
    let!(:professional) do
      user_with_role("professional", world, branch: world.branch_a1, user: own_user) if own_user
      professional_in(world.company_a, display_name: "Ana", user_id: own_user&.id)
    end
    let!(:assignment) { assign(professional, world.branch_a1) }
    let(:professional_id) { professional.id }
    let(:other_professional) { professional_in(world.company_a, display_name: "Beto").tap { assign(it, world.branch_a1) } }

    get "Lista las ausencias de un profesional" do
      tags "Ausencias"
      description "Exige `appointments.time_off.read` en la sucursal, o `appointments.time_off.manage_own` si el registro es del propio usuario y está asignado " \
                  "a la sucursal. El profesional debe estar asignado a la sucursal de la ruta (si no, 404). Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      let!(:mine) { time_off_for({ professional: }, reason: "Vacaciones") }
      let!(:theirs) { time_off_for({ professional: other_professional }) }

      response "200", "solo las ausencias del profesional de la ruta" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ mine.id ])
          expect(response.parsed_body["data"].first).to include("professional_id" => professional.id, "resource_id" => nil, "starts_at" => "2026-11-16T09:00:00.000Z",
                                                                "ends_at" => "2026-11-16T13:00:00.000Z", "reason" => "Vacaciones")
        end
      end

      response "200", "el profesional lee sus PROPIAS ausencias" do
        let(:own_user) { person }
        let!(:signed_in) { sign_in(person) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ mine.id ]) }
      end

      response "403", "el profesional NO lee las ausencias de otro profesional" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    post "Crea una ausencia de un profesional" do
      tags "Ausencias"
      description "Exige `appointments.time_off.manage` en la sucursal (sobre un profesional asignado a ella), o `appointments.time_off.manage_own` para el propio " \
                  "profesional. `starts_at` y `ends_at` son instantes (ISO 8601) con `starts_at < ends_at` y hasta 366 días. `reason` es texto libre opcional (hasta " \
                  "200 caracteres): NO escribas datos de salud; no se registra en logs ni en la auditoría. Ausencias solapadas del mismo dueño están permitidas. " \
                  "Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/TimeOffInput" }

      let(:body) { absence }

      response "201", "el profesional crea una ausencia para sí mismo" do
        let(:own_user) { person }
        let!(:signed_in) { sign_in(person) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("professional_id" => professional.id, "resource_id" => nil, "starts_at" => "2026-11-16T09:00:00.000Z", "reason" => "Congreso")
          expect(stored_time_offs.sole).to have_attributes(professional_id: professional.id, company_id: world.company_a.id)
          event = audit_events("time_off.created").sole
          expect(event.attributes.slice("before", "after", "metadata").to_json).not_to include("Congreso")
        end
      end

      response "403", "el profesional NO crea una ausencia para otro profesional de su sucursal" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored_time_offs).to be_empty
        end
      end

      response "404", "el profesional con su ausencia 'propia' en una sucursal donde NO está asignado" do
        let(:own_user) { person }
        let!(:signed_in) { sign_in(person) }
        let!(:unassigned) { with_tenant(world.organization) { Appointments::ProfessionalBranchAssignment.where(professional_id: professional.id).destroy_all } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end

      response "201", "el branch_manager crea la ausencia de un profesional asignado a SU sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema single_schema

        run_test! { expect(stored_time_offs.size).to eq(1) }
      end

      response "403", "el receptionist lee pero no escribe ausencias" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end

      response "404", "un profesional que no está asignado a la sucursal de la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_a).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end

      response "422", "fin igual o anterior al inicio" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { absence.merge(ends_at: "2026-11-16T09:00:00Z") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "ends_at", "code" => "invalid"))
          expect(stored_time_offs).to be_empty
        end
      end

      response "422", "una fecha ilegible y un motivo de más de 200 caracteres" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { starts_at: "mañana", ends_at: "2026-11-16T09:00:00Z", reason: "a" * 201 } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "starts_at", "code" => "blank"), a_hash_including("field" => "reason", "code" => "too_long"))
        end
      end

      response "422", "un profesional archivado no admite ausencias (`base: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:archived) { with_tenant(world.organization) { professional.update!(archived_at: Time.current) } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived")) }
      end

      response "400", "un campo con el tipo equivocado" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { starts_at: 123 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/professionals/{professional_id}/time_offs/{professional_time_off_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_time_off_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de una ausencia DE ESE profesional"

    let(:person) { create(:user) }
    let!(:own_membership) { user_with_role("professional", world, branch: world.branch_a1, user: person) }
    let!(:professional) { professional_in(world.company_a, display_name: "Ana", user_id: person.id) }
    let!(:other) { professional_in(world.company_a, display_name: "Beto") }
    let!(:assignments) { [ assign(professional, world.branch_a1), assign(other, world.branch_a1) ] }
    let!(:mine) { time_off_for({ professional: }, reason: "Vacaciones") }
    let!(:theirs) { time_off_for({ professional: other }, reason: "Cirugía") }
    let(:professional_id) { professional.id }
    let(:professional_time_off_id) { mine.id }

    delete "Borra una ausencia de un profesional" do
      tags "Ausencias"
      description "Mismos permisos que crearla. La ausencia se busca SOLO entre las del profesional de la ruta: la de otro profesional es 404 aunque exista. " \
                  "Borrado real (una ausencia no tiene historial que preservar), auditado por id sin el motivo."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "el profesional borra su propia ausencia, auditada sin el motivo" do
        let!(:signed_in) { sign_in(person) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(stored_time_offs.map(&:id)).to eq([ theirs.id ])
          expect(audit_events("time_off.deleted").sole.attributes.slice("before", "after", "metadata").to_json).not_to include("Vacaciones")
        end
      end

      response "204", "el branch_manager borra la de un profesional de su sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:professional_time_off_id) { theirs.id }
        let(:professional_id) { other.id }

        run_test! { expect(stored_time_offs.map(&:id)).to eq([ mine.id ]) }
      end

      response "404", "el profesional borra la ausencia de OTRO por su propia URL: la fila sobrevive" do
        let!(:signed_in) { sign_in(person) }
        let(:professional_time_off_id) { theirs.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(stored_time_offs.map(&:id)).to contain_exactly(mine.id, theirs.id)
        end
      end

      response "403", "el profesional borra la ausencia de otro por la URL de ESE otro: la fila sobrevive" do
        let!(:signed_in) { sign_in(person) }
        let(:professional_id) { other.id }
        let(:professional_time_off_id) { theirs.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored_time_offs.map(&:id)).to contain_exactly(mine.id, theirs.id)
        end
      end

      response "403", "el receptionist no borra ausencias" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end

      response "404", "un id que no existe" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_time_off_id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/resources/{resource_id}/time_offs" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :resource_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de un recurso de la sucursal de la ruta"

    let!(:resource) { create_in(world.organization, :resource, branch: world.branch_a1) }
    let(:resource_id) { resource.id }
    let(:foreign_resource) { create_in(world.organization, :resource, branch: world.branch_a2) }

    get "Lista las ausencias de un recurso" do
      tags "Ausencias"
      description "Exige `appointments.time_off.read` en la sucursal. El recurso debe ser de la sucursal de la ruta. Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      let!(:closed) { time_off_for({ resource: }) }

      response "200", "las ausencias del recurso" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].first).to include("id" => closed.id, "resource_id" => resource.id, "professional_id" => nil) }
      end

      response "403", "el profesional no lee las ausencias de los recursos" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "un recurso de otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { foreign_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    post "Crea una ausencia de un recurso" do
      tags "Ausencias"
      description "Exige `appointments.time_off.manage` en la sucursal. Mismas reglas de intervalo que la ausencia de un profesional. Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/TimeOffInput" }

      let(:body) { absence.except(:reason) }

      response "201", "el branch_manager bloquea un recurso de su sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("resource_id" => resource.id, "professional_id" => nil, "reason" => nil)
          expect(stored_time_offs.sole).to have_attributes(resource_id: resource.id, owner_type: "resource")
        end
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} no crea ausencias de recursos" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(stored_time_offs).to be_empty }
        end
      end

      response "404", "un recurso de otra sucursal: ni el company_manager lo alcanza por esta ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { foreign_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs).to be_empty }
      end

      response "422", "fin anterior al inicio" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { absence.merge(ends_at: "2026-11-16T08:00:00Z") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test!
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/resources/{resource_id}/time_offs/{resource_time_off_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :resource_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :resource_time_off_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de una ausencia DE ESE recurso"

    let!(:resource) { create_in(world.organization, :resource, branch: world.branch_a1) }
    let!(:other_resource) { create_in(world.organization, :resource, branch: world.branch_a1) }
    let!(:closed) { time_off_for({ resource: }) }
    let!(:other_closed) { time_off_for({ resource: other_resource }) }
    let(:resource_id) { resource.id }
    let(:resource_time_off_id) { closed.id }

    delete "Borra una ausencia de un recurso" do
      tags "Ausencias"
      description "Exige `appointments.time_off.manage` en la sucursal. La ausencia se busca SOLO entre las del recurso de la ruta."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "el branch_manager borra la ausencia del recurso" do
        let!(:signed_in) { sign_in(branch_manager) }

        run_test! { expect(stored_time_offs.map(&:id)).to eq([ other_closed.id ]) }
      end

      response "404", "la ausencia de OTRO recurso por la URL de este: la fila sobrevive" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_time_off_id) { other_closed.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end

      response "403", "el receptionist no borra" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_time_offs.size).to eq(2) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
