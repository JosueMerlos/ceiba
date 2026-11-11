require "swagger_helper"

# The resources of a BRANCH (chairs, rooms, equipment). Everything is asked at the branch of the route: reading needs
# `appointments.resource.read`, writing `appointments.resource.manage`, so a branch role only reaches its own branch (a sibling
# is a 404) and the lookup is restricted to that branch's resources (another branch's resource is a 404, never reachable by id).
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: recursos de una sucursal" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let(:branch_manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  list_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/Resource" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }
  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Resource" } } }

  def resource_in(branch, **attributes) = create_in(world.organization, :resource, branch:, **attributes)
  def stored(id) = with_tenant(world.organization) { Appointments::Resource.find(id) }
  def resource_count = with_tenant(world.organization) { Appointments::Resource.count }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/resources" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Lista los recursos no archivados de la sucursal" do
      tags "Recursos"
      description "Exige `appointments.resource.read` en la sucursal. Devuelve los recursos no archivados (activos y pausados) de ESA sucursal, " \
                  "en orden de creación (el cursor es el id). Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      let!(:chair) { resource_in(world.branch_a1, name: "Sillón 1") }
      let!(:paused) { resource_in(world.branch_a1, name: "Sala 1", kind: "room", active: false) }
      let!(:archived) { resource_in(world.branch_a1, name: "Vieja", archived_at: Time.current) }
      let!(:sibling) { resource_in(world.branch_a2, name: "Sillón hermano") }

      response "200", "los recursos no archivados de la sucursal, sin los de otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ chair.id, paused.id ])
          expect(response.parsed_body["data"].first).to include("name" => "Sillón 1", "kind" => "chair", "branch_id" => world.branch_a1.id, "active" => true, "archived_at" => nil)
        end
      end

      %w[branch_manager receptionist professional].each do |role|
        response "200", "el #{role} de la sucursal los lee" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema list_schema

          run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ chair.id, paused.id ]) }
        end
      end

      response "200", "paginado por cursor" do
        let!(:signed_in) { sign_in(manager) }
        let(:limit) { 1 }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ chair.id ])
          expect(response.parsed_body["page"]["has_more"]).to be(true)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "un rol de organización no tiene permiso de recursos" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
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

    post "Crea un recurso en la sucursal" do
      tags "Recursos"
      description "Exige `appointments.resource.manage` en la sucursal. `kind` es `chair`, `room` o `equipment`. Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ResourceInput" }

      let(:body) { { name: "Sala 1", kind: "room" } }

      response "201", "el recurso creado en la sucursal de la ruta, auditado" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("name" => "Sala 1", "kind" => "room", "branch_id" => world.branch_a1.id, "active" => true)
          expect(stored(response.parsed_body["data"]["id"])).to have_attributes(company_id: world.company_a.id, branch_id: world.branch_a1.id)
          expect(audit_events("resource.created").size).to eq(1)
        end
      end

      response "201", "el branch_manager lo crea en SU sucursal" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema single_schema

        run_test! { expect(resource_count).to eq(1) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} no crea recursos" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(resource_count).to eq(0) }
        end
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(resource_count).to eq(0) }
      end

      response "404", "una sucursal de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(resource_count).to eq(0) }
      end

      response "422", "un tipo desconocido y un nombre en blanco" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: " ", kind: "spaceship" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "name", "code" => "blank"), a_hash_including("field" => "kind", "code" => "inclusion"))
          expect(resource_count).to eq(0)
        end
      end

      response "400", "un campo con el tipo equivocado" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: 123 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(resource_count).to eq(0) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/resources/{resource_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :resource_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del recurso"

    let!(:resource) { resource_in(world.branch_a1, name: "Sala 1", kind: "room") }
    let(:resource_id) { resource.id }
    let(:sibling_resource) { resource_in(world.branch_a2, name: "Sala hermana") }

    get "Obtiene un recurso de la sucursal" do
      tags "Recursos"
      description "Exige `appointments.resource.read` en la sucursal. Un recurso de otra sucursal responde 404."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el recurso" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => resource.id, "name" => "Sala 1") }
      end

      response "404", "un recurso de otra sucursal de la misma empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { sibling_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "un id que no existe" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    patch "Edita un recurso" do
      tags "Recursos"
      description "Exige `appointments.resource.manage` en la sucursal. Solo cambian los campos enviados. Un archivado no se edita (422)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ResourcePatch" }

      let(:body) { { name: "Sala 2", active: false } }

      response "200", "el recurso editado, auditado con antes y después" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("name" => "Sala 2", "active" => false, "kind" => "room")
          expect(audit_events("resource.updated").sole.before).to eq("name" => "Sala 1", "active" => true)
        end
      end

      response "403", "el receptionist no edita recursos" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(resource.id).name).to eq("Sala 1") }
      end

      response "404", "un recurso de otra sucursal: ni el company_manager lo alcanza por esta ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { sibling_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(sibling_resource.id).name).to eq("Sala hermana") }
      end

      response "422", "un archivado no se edita (`base: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:resource) { resource_in(world.branch_a1, archived_at: Time.current) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived")) }
      end

      response "422", "un nombre en blanco" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: "  " } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { expect(stored(resource.id).name).to eq("Sala 1") }
      end
    end

    delete "Archiva un recurso" do
      tags "Recursos"
      description "Exige `appointments.resource.manage` en la sucursal. No borra: lo archiva (`archived_at`) y deja de listarse. Es idempotente."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "el recurso queda archivado (no borrado) y auditado" do
        let!(:signed_in) { sign_in(branch_manager) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(stored(resource.id)).to be_archived
          expect(audit_events("resource.archived").size).to eq(1)
        end
      end

      response "403", "el receptionist no archiva recursos" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(resource.id)).not_to be_archived }
      end

      response "404", "un recurso de otra sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let(:resource_id) { sibling_resource.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(sibling_resource.id)).not_to be_archived }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
