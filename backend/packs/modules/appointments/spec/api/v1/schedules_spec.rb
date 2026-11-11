require "swagger_helper"

# Weekly hours of a branch, of a professional and of a resource, always under a BRANCH route: the permission is asked at the
# branch (`appointments.schedule.read|manage`; the professional reads their own with `schedule.read_own`), and the owner is
# searched among the ones that belong to that branch (an assigned professional, the branch's resource), so another branch's
# owner is a 404 for everybody. PUT replaces ALL the owner's slots in that branch.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: horarios semanales" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let(:branch_manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  let(:nine_to_one) { { weekday: 1, starts_at_local: "09:00", ends_at_local: "13:00" } }
  let(:overlapping) { [ nine_to_one, { weekday: 1, starts_at_local: "12:00", ends_at_local: "15:00" } ] }

  list_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { type: :array, items: { "$ref" => "#/components/schemas/WeeklyScheduleSlot" } } } }

  def professional_in(company, **attributes) = create_in(world.organization, :professional, company:, **attributes)
  def assign(professional, branch) = create_in(world.organization, :professional_branch_assignment, professional:, branch:)
  def slot_in(branch, **owner) = create_in(world.organization, :weekly_schedule, branch:, **owner)
  def slots_of(**owner) = with_tenant(world.organization) { Appointments::WeeklySchedule.where(**owner).order(:weekday, :starts_at_local).map { [ it.branch_id, it.weekday, Appointments::WeeklySchedule.clock(it.starts_at_local), Appointments::WeeklySchedule.clock(it.ends_at_local) ] } }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/professionals/{professional_id}/schedule" do
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

    get "Horario semanal de un profesional en la sucursal" do
      tags "Horarios"
      description "Exige `appointments.schedule.read` en la sucursal, o `appointments.schedule.read_own` si el registro es del propio usuario y está " \
                  "asignado a la sucursal. Devuelve solo las franjas de ESA sucursal. El profesional debe estar asignado a la sucursal de la ruta (si no, 404)."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      let!(:monday) { slot_in(world.branch_a1, professional:, weekday: 1) }
      let!(:elsewhere) { assign(professional, world.branch_a2).then { slot_in(world.branch_a2, professional:, weekday: 2) } }

      response "200", "las franjas de la sucursal de la ruta, no las de otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to eq([ { "id" => monday.id, "weekday" => 1, "starts_at_local" => "09:00", "ends_at_local" => "13:00" } ])
        end
      end

      response "200", "el receptionist lee los horarios" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].size).to eq(1) }
      end

      response "200", "el profesional lee su PROPIO horario con schedule.read_own" do
        let(:own_user) { person }
        let!(:signed_in) { sign_in(person) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ monday.id ]) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el profesional NO lee el horario de otro profesional" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "un profesional que no está asignado a la sucursal de la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_a).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    put "Reemplaza el horario semanal de un profesional en la sucursal" do
      tags "Horarios"
      description "Exige `appointments.schedule.manage` en la sucursal. Reemplaza TODAS las franjas del profesional en esa sucursal en una transacción: lo que no " \
                  "viene se quita y una lista vacía quita todo. Las horas son locales de la sucursal (`HH:MM`, minutos enteros, sin cruzar la medianoche); " \
                  "`weekday` va de 0 (domingo) a 6. Franjas que se solapan (también con las del profesional en otras sucursales) dan 422 con `slots: overlap`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/WeeklyScheduleInput" }

      let(:body) { { slots: [ nine_to_one, { weekday: 1, starts_at_local: "14:00", ends_at_local: "18:00" }, { weekday: 3, starts_at_local: "09:00", ends_at_local: "13:00" } ] } }

      response "200", "las franjas quedan reemplazadas y auditadas" do
        let!(:signed_in) { sign_in(manager) }
        let!(:old) { slot_in(world.branch_a1, professional:, weekday: 5) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("weekday", "starts_at_local", "ends_at_local")).to eq([ [ 1, "09:00", "13:00" ], [ 1, "14:00", "18:00" ], [ 3, "09:00", "13:00" ] ])
          expect(slots_of(professional_id: professional.id).size).to eq(3)
          expect(audit_events("schedule.replaced").sole.metadata).to include("branch_id" => world.branch_a1.id)
        end
      end

      response "200", "el branch_manager gestiona el horario de su sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema list_schema

        run_test! { expect(slots_of(professional_id: professional.id).size).to eq(3) }
      end

      response "200", "una lista vacía quita todas las franjas de la sucursal y deja las de las otras" do
        let!(:signed_in) { sign_in(manager) }
        let!(:here) { slot_in(world.branch_a1, professional:, weekday: 5) }
        let!(:there) { assign(professional, world.branch_a2).then { slot_in(world.branch_a2, professional:, weekday: 2) } }
        let(:body) { { slots: [] } }
        schema list_schema

        run_test! { expect(slots_of(professional_id: professional.id)).to eq([ [ world.branch_a2.id, 2, "09:00", "13:00" ] ]) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el receptionist lee pero no escribe horarios" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(professional_id: professional.id)).to be_empty }
      end

      response "403", "el profesional ve su horario pero no lo edita" do
        let(:own_user) { person }
        let!(:signed_in) { sign_in(person) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(professional_id: professional.id)).to be_empty }
      end

      response "404", "un profesional que no está asignado a la sucursal (la base de datos no llega a verlo)" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { professional_in(world.company_a).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(professional_id: professional_id)).to be_empty }
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(professional_id: professional.id)).to be_empty }
      end

      response "422", "el lunes 9-13 y 12-15 se solapan: `slots: overlap` y no cambia nada" do
        let!(:signed_in) { sign_in(manager) }
        let!(:old) { slot_in(world.branch_a1, professional:, weekday: 5) }
        let(:body) { { slots: overlapping } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "slots", "code" => "overlap"))
          expect(slots_of(professional_id: professional.id)).to eq([ [ world.branch_a1.id, 5, "09:00", "13:00" ] ])
        end
      end

      response "422", "se solapa con el horario del mismo profesional en OTRA sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let!(:there) { assign(professional, world.branch_a2).then { slot_in(world.branch_a2, professional:, weekday: 1, starts_at_local: "12:00", ends_at_local: "15:00") } }
        let(:body) { { slots: [ nine_to_one ] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "slots", "code" => "overlap"))
          expect(slots_of(professional_id: professional.id)).to eq([ [ world.branch_a2.id, 1, "12:00", "15:00" ] ])
        end
      end

      response "422", "una franja con segundos (10:00:30) es inválida: precisión de minuto" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { slots: [ { weekday: 1, starts_at_local: "10:00", ends_at_local: "10:00:30" } ] } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "slots", "code" => "invalid"))
          expect(slots_of(professional_id: professional.id)).to be_empty
        end
      end

      response "422", "un profesional archivado no admite horario (`base: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:archived) { with_tenant(world.organization) { professional.update!(archived_at: Time.current) } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived")) }
      end

      response "400", "sin la lista de franjas, con una que no es un objeto o con un tipo equivocado" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { slots: [ { weekday: "lunes", starts_at_local: "09:00", ends_at_local: "13:00" } ] } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(professional_id: professional.id)).to be_empty }
      end

      response "400", "demasiadas franjas" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { slots: Array.new(101) { { weekday: 1, starts_at_local: "09:00", ends_at_local: "10:00" } } } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end

  # One person with a record in each company of the group: each company has its own, independent hours.
  describe "una persona con registros en dos empresas del grupo" do
    let(:person) { create(:user) }
    let!(:memberships) { [ user_with_role("professional", world, branch: world.branch_a1, user: person), user_with_role("professional", world, branch: world.branch_b1, user: person) ] }
    let!(:in_a) { professional_in(world.company_a, display_name: "Sandra en A", user_id: person.id) }
    let!(:in_b) { professional_in(world.company_b, display_name: "Sandra en B", user_id: person.id) }
    let!(:hours_a) { assign(in_a, world.branch_a1).then { slot_in(world.branch_a1, professional: in_a, weekday: 2) } }
    let!(:hours_b) { assign(in_b, world.branch_b1).then { slot_in(world.branch_b1, professional: in_b, weekday: 5) } }

    it "cada empresa ve solo su horario, y el registro de la otra no se encuentra" do
      session = sign_in(person)
      base = "/api/v1/organizations/#{world.organization.id}/companies"

      get "#{base}/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/professionals/#{in_a.id}/schedule", headers: session.csrf_headers
      listed_in_a = response.parsed_body["data"].pluck("weekday")
      get "#{base}/#{world.company_b.id}/appointments/branches/#{world.branch_b1.id}/professionals/#{in_b.id}/schedule", headers: session.csrf_headers
      listed_in_b = response.parsed_body["data"].pluck("weekday")
      get "#{base}/#{world.company_a.id}/appointments/branches/#{world.branch_a1.id}/professionals/#{in_b.id}/schedule", headers: session.csrf_headers

      expect([ listed_in_a, listed_in_b ]).to eq([ [ 2 ], [ 5 ] ])
      expect(response).to have_http_status(:not_found)
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/schedule" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Horario semanal de la sucursal" do
      tags "Horarios"
      description "Exige `appointments.schedule.read` en la sucursal. Una sucursal sin franjas está cerrada."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      let!(:monday) { slot_in(world.branch_a1) }
      let!(:other_branch) { slot_in(world.branch_a2, weekday: 2) }

      response "200", "las franjas de la sucursal, sin las de otra" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ monday.id ]) }
      end

      response "403", "el profesional no lee el horario de la sucursal (solo el suyo)" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "una sucursal hermana a la que el receptionist no pertenece" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    put "Reemplaza el horario semanal de la sucursal" do
      tags "Horarios"
      description "Exige `appointments.schedule.manage` en la sucursal. Reemplaza TODAS las franjas de la sucursal; mismas reglas que el horario de un profesional."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/WeeklyScheduleInput" }

      let(:body) { { slots: [ { weekday: 1, starts_at_local: "08:00", ends_at_local: "18:00" }, { weekday: 2, starts_at_local: "08:00", ends_at_local: "18:00" } ] } }

      response "200", "el branch_manager reemplaza el horario de SU sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:old) { slot_in(world.branch_a1, weekday: 6) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("weekday")).to eq([ 1, 2 ])
          expect(slots_of(owner_type: "branch", branch_id: world.branch_a1.id).size).to eq(2)
        end
      end

      response "403", "el receptionist no escribe el horario de la sucursal" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(owner_type: "branch")).to be_empty }
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(owner_type: "branch")).to be_empty }
      end

      response "422", "franjas de la sucursal que se solapan" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { slots: overlapping } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "slots", "code" => "overlap")) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/resources/{resource_id}/schedule" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :resource_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID de un recurso de la sucursal de la ruta"

    let!(:resource) { create_in(world.organization, :resource, branch: world.branch_a1) }
    let(:resource_id) { resource.id }
    let(:foreign_resource) { create_in(world.organization, :resource, branch: world.branch_a2) }

    get "Horario semanal de un recurso" do
      tags "Horarios"
      description "Exige `appointments.schedule.read` en la sucursal. El recurso debe ser de la sucursal de la ruta."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      let!(:monday) { slot_in(world.branch_a1, resource:) }

      response "200", "las franjas del recurso" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ monday.id ]) }
      end

      response "404", "un recurso de otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { foreign_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    put "Reemplaza el horario semanal de un recurso" do
      tags "Horarios"
      description "Exige `appointments.schedule.manage` en la sucursal. Mismas reglas que el horario de un profesional."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/WeeklyScheduleInput" }

      let(:body) { { slots: [ nine_to_one ] } }

      response "200", "el branch_manager reemplaza el horario del recurso" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema list_schema

        run_test! { expect(slots_of(resource_id: resource.id)).to eq([ [ world.branch_a1.id, 1, "09:00", "13:00" ] ]) }
      end

      response "403", "el receptionist no escribe" do
        let!(:signed_in) { sign_in(receptionist) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(resource_id: resource.id)).to be_empty }
      end

      response "404", "un recurso de otra sucursal: ni el company_manager lo alcanza por esta ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { foreign_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(slots_of(resource_id: foreign_resource.id)).to be_empty }
      end

      response "422", "franjas del recurso que se solapan" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { slots: overlapping } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "slots", "code" => "overlap")) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
