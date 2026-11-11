require "swagger_helper"

# The professionals of a company. They are COMPANY records: reading needs `appointments.professional.read` (branch roles
# have it through from_descendants), writing needs `appointments.professional.manage` (company_manager only). The person's
# own profile is read from the branch where they are assigned with `appointments.professional.read_own`.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: profesionales" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  list_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/Professional" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }
  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Professional" } } }

  def professional_in(company, **attributes) = create_in(world.organization, :professional, company:, **attributes)
  def assign(professional, branch) = create_in(world.organization, :professional_branch_assignment, professional:, branch:)
  def stored(id) = with_tenant(world.organization) { Appointments::Professional.find(id) }
  def professional_count = with_tenant(world.organization) { Appointments::Professional.count }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/professionals" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Lista los profesionales no archivados de la empresa" do
      tags "Profesionales"
      description "Exige `appointments.professional.read` en la empresa (los roles de sucursal con ese permiso lo tienen por `from_descendants`). " \
                  "Devuelve los profesionales no archivados, con las sucursales a las que están asignados y los servicios que prestan; no trae " \
                  "datos de la persona vinculada (solo su `user_id`). Va en orden de creación (el cursor es el id). Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      let!(:ana) { professional_in(world.company_a, display_name: "Ana") }
      let!(:beto) { professional_in(world.company_a, display_name: "Beto", active: false) }
      let!(:archived) { professional_in(world.company_a, display_name: "Viejo", archived_at: Time.current) }
      let!(:foreign) { professional_in(world.company_b, display_name: "Foráneo") }
      let!(:ana_assignment) { assign(ana, world.branch_a1) }
      let!(:ana_service) { create_in(world.organization, :professional_service, professional: ana, service: create_in(world.organization, :service, company: world.company_a)) }

      response "200", "los profesionales no archivados de la empresa, con sus sucursales y servicios, sin los de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id, beto.id ])
          expect(response.parsed_body["data"].first).to include("display_name" => "Ana", "active" => true, "archived_at" => nil, "user_id" => nil,
                                                                "branch_ids" => [ world.branch_a1.id ], "service_ids" => [ ana_service.service_id ])
          expect(response.parsed_body["data"].second).to include("active" => false, "branch_ids" => [], "service_ids" => [])
        end
      end

      %w[branch_manager receptionist].each do |role|
        response "200", "el #{role} de una sucursal de la empresa también los lee (from_descendants)" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema list_schema

          run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id, beto.id ]) }
        end
      end

      response "200", "paginado por cursor" do
        let!(:signed_in) { sign_in(manager) }
        let(:limit) { 1 }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id ])
          expect(response.parsed_body["page"]["has_more"]).to be(true)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "el profesional solo ve su perfil: no lista a los demás (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "403", "un rol de organización no tiene permiso de profesionales" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "la empresa de otro grupo: el recepcionista de A no ve la empresa B" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        let(:company_id) { world.company_b.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end

    post "Crea un profesional" do
      tags "Profesionales"
      description "Exige `appointments.professional.manage`. `user_id` vincula al profesional con una persona y debe tener una membresía en la " \
                  "organización (si no, 422); una persona tiene a lo sumo un registro por empresa. Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ProfessionalInput" }

      let(:person) { create(:user) }
      let(:body) { { display_name: "Sandra Gómez" } }

      response "201", "el profesional creado en la empresa de la ruta, sin sucursales ni servicios" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("display_name" => "Sandra Gómez", "active" => true, "archived_at" => nil, "user_id" => nil, "branch_ids" => [], "service_ids" => [])
          expect(stored(data["id"]).company_id).to eq(world.company_a.id)
          expect(audit_events("professional.created").map(&:auditable_id)).to eq([ data["id"] ])
        end
      end

      response "201", "vinculado a una persona que es miembro de la organización" do
        let!(:signed_in) { sign_in(manager) }
        let!(:membership) { user_with_role("receptionist", world, branch: world.branch_a1, user: person) }
        let(:body) { { display_name: "Sandra", user_id: person.id } }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("user_id" => person.id) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} no crea profesionales" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(professional_count).to eq(0)
          end
        end
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(professional_count).to eq(0) }
      end

      response "422", "una persona sin membresía en la organización (`user_id: invalid`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { display_name: "Sandra", user_id: person.id } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "user_id", "code" => "invalid"))
          expect(professional_count).to eq(0)
        end
      end

      response "422", "un `user_id` que no es un UUID (`user_id: invalid`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { display_name: "Sandra", user_id: "no-es-un-uuid" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "user_id", "code" => "invalid"))
          expect(professional_count).to eq(0)
        end
      end

      response "422", "la misma persona dos veces en la empresa (`user_id: taken`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:membership) { user_with_role("receptionist", world, branch: world.branch_a1, user: person) }
        let!(:existing) { professional_in(world.company_a, user_id: person.id) }
        let(:body) { { display_name: "Otra vez", user_id: person.id } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "user_id", "code" => "taken"))
          expect(professional_count).to eq(1)
        end
      end

      response "422", "sin nombre (`display_name: blank`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { display_name: " " } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "display_name", "code" => "blank"))
          expect(professional_count).to eq(0)
        end
      end

      response "400", "un campo con el tipo equivocado" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { display_name: 123 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(professional_count).to eq(0) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/professionals/{professional_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional"

    let!(:professional) { professional_in(world.company_a, display_name: "Ana") }
    let(:professional_id) { professional.id }
    let(:foreign) { professional_in(world.company_b, display_name: "Foráneo") }

    get "Obtiene un profesional" do
      tags "Profesionales"
      description "Exige `appointments.professional.read` en la empresa. Un profesional de otra empresa responde 404. Un archivado se puede ver, con `archived_at`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el profesional" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => professional.id, "display_name" => "Ana") }
      end

      response "200", "uno archivado se puede ver" do
        let!(:signed_in) { sign_in(manager) }
        let!(:professional) { professional_in(world.company_a, archived_at: Time.current) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]["archived_at"]).to be_present }
      end

      response "403", "el profesional no lee fichas por la ruta de empresa (solo la suya por la de sucursal)" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "un id que no existe" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    patch "Edita un profesional" do
      tags "Profesionales"
      description "Exige `appointments.professional.manage`. Solo cambian los campos enviados; `user_id` solo se puede fijar una vez: si ya está vinculado no cambia ni se quita (422 `immutable`; para cambiar de persona se archiva y se crea otro profesional). Un archivado no se edita (422)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ProfessionalPatch" }

      let(:body) { { display_name: "Ana María", active: false } }

      response "200", "el profesional editado, auditado con antes y después" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("display_name" => "Ana María", "active" => false)
          expect(stored(professional.id)).to have_attributes(display_name: "Ana María", active: false, company_id: world.company_a.id)
          expect(audit_events("professional.updated").map(&:auditable_id)).to eq([ professional.id ])
        end
      end

      response "403", "el recepcionista no edita" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(professional.id).display_name).to eq("Ana") }
      end

      response "404", "un profesional de otra empresa no se edita" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(foreign.id).display_name).to eq("Foráneo") }
      end

      response "422", "un nombre en blanco" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { display_name: "" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "display_name", "code" => "blank"))
          expect(stored(professional.id).display_name).to eq("Ana")
        end
      end

      response "422", "un `user_id` que no es un UUID en un profesional sin vincular (`user_id: invalid`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { user_id: "no-es-un-uuid" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "user_id", "code" => "invalid"))
          expect(stored(professional.id).user_id).to be_nil
        end
      end

      [ "", "  " ].each do |blank|
        response "422", "un `user_id` en blanco (#{blank.inspect}) en un profesional sin vincular (`user_id: invalid`)" do
          let!(:signed_in) { sign_in(manager) }
          let(:body) { { user_id: blank } }
          schema "$ref" => "#/components/schemas/ValidationProblem"

          run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "user_id", "code" => "invalid")) }
        end
      end

      response "200", "un profesional sin vincular se vincula una vez a una persona con membresía" do
        let!(:signed_in) { sign_in(manager) }
        let(:person) { create(:user) }
        let!(:membership) { user_with_role("receptionist", world, branch: world.branch_a1, user: person) }
        let(:body) { { user_id: person.id } }
        schema single_schema

        run_test! { expect(stored(professional.id).user_id).to eq(person.id) }
      end

      context "con un profesional ya vinculado" do
        let(:person) { create(:user) }
        let(:other_person) { create(:user) }
        let!(:professional) do
          user_with_role("receptionist", world, branch: world.branch_a1, user: person)
          user_with_role("receptionist", world, branch: world.branch_a1, user: other_person)
          professional_in(world.company_a, display_name: "Ana", user_id: person.id)
        end

        {
          "otra persona" => -> { { user_id: other_person.id } },
          "null" => -> { { user_id: nil } },
          "un texto que no es UUID" => -> { { user_id: "no-es-un-uuid" } },
          "un texto en blanco" => -> { { user_id: "" } }
        }.each do |label, change|
          response "422", "cambiar el `user_id` a #{label} es `user_id: immutable` y conserva el vínculo" do
            let!(:signed_in) { sign_in(manager) }
            let(:body) { instance_exec(&change) }
            schema "$ref" => "#/components/schemas/ValidationProblem"

            run_test! do |response|
              expect(response.parsed_body["errors"].select { it["field"] == "user_id" }.map { it["code"] }).to eq([ "immutable" ])
              expect(stored(professional.id).user_id).to eq(person.id)
            end
          end
        end

        response "200", "reenviar el mismo `user_id` no es un cambio" do
          let!(:signed_in) { sign_in(manager) }
          let(:body) { { user_id: person.id, display_name: "Ana María" } }
          schema single_schema

          run_test! { expect(stored(professional.id)).to have_attributes(user_id: person.id, display_name: "Ana María") }
        end
      end

      response "422", "un profesional archivado (`base: archived`)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:professional) { professional_in(world.company_a, display_name: "Ana", archived_at: Time.current) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived")) }
      end
    end

    delete "Archiva un profesional" do
      tags "Profesionales"
      description "Exige `appointments.professional.manage`. No borra: archiva (`archived_at`), conserva sus asignaciones y servicios y deja de aparecer en el listado."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "archivado: la fila sigue y ya no está en el listado" do
        let!(:signed_in) { sign_in(manager) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(stored(professional.id).archived_at).to be_present
          expect(audit_events("professional.archived").map(&:auditable_id)).to eq([ professional.id ])
        end
      end

      response "403", "el branch_manager no archiva" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(professional.id).archived_at).to be_nil }
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:professional_id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored(foreign.id).archived_at).to be_nil }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/professionals/{professional_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Sucursal desde la que se mira el perfil"
    parameter name: :professional_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del profesional"

    let(:person) { create(:user) }
    let!(:own_membership) { user_with_role("professional", world, branch: world.branch_a1, user: person) }
    let!(:professional) { professional_in(world.company_a, display_name: "Sandra", user_id: person.id) }
    let!(:assignment) { assign(professional, world.branch_a1) }
    let(:professional_id) { professional.id }

    get "Obtiene un profesional desde una sucursal" do
      tags "Profesionales"
      description "Es la ruta del perfil propio del `professional`: exige `appointments.professional.read` en la sucursal, o bien " \
                  "`appointments.professional.read_own` en la sucursal cuando el registro está vinculado a su usuario y asignado a esa sucursal."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el profesional lee su propio perfil en la sucursal donde está asignado" do
        let!(:signed_in) { sign_in(person) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => professional.id, "user_id" => person.id, "branch_ids" => [ world.branch_a1.id ]) }
      end

      response "200", "el branch_manager lee cualquier profesional de la empresa desde su sucursal" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let!(:other) { professional_in(world.company_a, display_name: "Sin asignar") }
        let(:professional_id) { other.id }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => other.id) }
      end

      response "403", "el profesional no lee el perfil de OTRO profesional" do
        let!(:signed_in) { sign_in(person) }
        let!(:other) { professional_in(world.company_a, display_name: "Otro") }
        let!(:other_assignment) { assign(other, world.branch_a1) }
        let(:professional_id) { other.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "403", "el profesional no lee su perfil desde una sucursal donde NO está asignado" do
        let!(:signed_in) { sign_in(person) }
        let!(:second_membership) { user_with_role("professional", world, branch: world.branch_a2, user: person) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "una sucursal hermana a la que el profesional no pertenece" do
        let!(:signed_in) { sign_in(person) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "un profesional de otra empresa" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        let(:professional_id) { professional_in(world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(person) }
        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
