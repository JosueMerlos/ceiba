require "swagger_helper"

# The service catalog of a company. Services are COMPANY records: reading needs `appointments.service.read` (branch roles
# have it through from_descendants), writing needs `appointments.service.manage` (company_manager only).
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: servicios del catálogo" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }
  let!(:modules_enabled) do
    with_tenant(world.organization) { [ world.company_a, world.company_b ].each { |company| Modules::Enable.call(company:, key: "appointments") } }
  end

  list_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/Service" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }
  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Service" } } }

  def service_in(company, **attributes) = create_in(world.organization, :service, company:, **attributes)
  def stored(id) = with_tenant(world.organization) { Appointments::Service.find(id) }
  def service_count = with_tenant(world.organization) { Appointments::Service.count }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Lista los servicios no archivados de la empresa" do
      tags "Servicios"
      description "Exige `appointments.service.read` en la empresa (los roles de sucursal la tienen por `from_descendants`). " \
                  "Devuelve los servicios no archivados, activos e inactivos; el filtro opcional `active` (`true` o `false`) deja solo " \
                  "los de ese estado. Los archivados no aparecen. Va en orden de creación (el cursor es el id); `position` " \
                  "es el orden de presentación que el cliente aplica. Paginado por cursor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :active, in: :query, schema: { type: :boolean }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      let!(:barba) { service_in(world.company_a, name: "Barba", position: 2) }
      let!(:corte) { service_in(world.company_a, name: "Corte", position: 1) }
      let!(:archived) { service_in(world.company_a, name: "Viejo", archived_at: Time.current) }
      let!(:inactive) { service_in(world.company_a, name: "Pausado", active: false) }
      let!(:foreign) { service_in(world.company_b, name: "Foráneo") }

      response "200", "los servicios no archivados de la empresa (activos e inactivos), sin servicios de otra empresa" do
        let!(:signed_in) { sign_in(manager) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ barba.id, corte.id, inactive.id ])
          expect(response.parsed_body["data"].second).to include("name" => "Corte", "position" => 1, "currency" => "NIO", "price_minor" => 20_000, "archived_at" => nil)
        end
      end

      response "200", "con active=false solo los inactivos" do
        let!(:signed_in) { sign_in(manager) }
        let(:active) { false }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ inactive.id ]) }
      end

      response "200", "con active=true solo los activos" do
        let!(:signed_in) { sign_in(manager) }
        let(:active) { true }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ barba.id, corte.id ]) }
      end

      response "400", "active debe ser true o false" do
        let!(:signed_in) { sign_in(manager) }
        let(:active) { "quizas" }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "200", "el #{role} de una sucursal de la empresa también lee el catálogo (from_descendants)" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema list_schema

          run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ barba.id, corte.id, inactive.id ]) }
        end
      end

      response "200", "paginado por cursor" do
        let!(:signed_in) { sign_in(manager) }
        let(:limit) { 1 }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ barba.id ])
          expect(response.parsed_body["page"]["has_more"]).to be(true)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "un rol de organización no tiene permiso de servicios (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "la empresa de otro grupo: el recepcionista de A no ve la empresa B" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        let(:company_id) { world.company_b.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }

        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end

    post "Crea un servicio" do
      tags "Servicios"
      description "Exige `appointments.service.manage`. `price_minor` es un entero en unidades menores. Sin `currency` toma la de la empresa; " \
                  "una moneda distinta responde 422 (`currency: mismatch`). Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ServiceInput" }

      let(:body) { { name: "Corte clásico", duration_minutes: 30, price_minor: 20_000, buffer_after_minutes: 5 } }

      response "201", "el servicio creado, con la moneda de la empresa" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("name" => "Corte clásico", "duration_minutes" => 30, "buffer_after_minutes" => 5, "price_minor" => 20_000, "currency" => "NIO", "active" => true, "archived_at" => nil)
          expect(stored(data["id"]).company_id).to eq(world.company_a.id)
          expect(audit_events("service.created").map(&:auditable_id)).to eq([ data["id"] ])
        end
      end

      response "201", "con la moneda de la empresa enviada de forma explícita" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: "Corte", duration_minutes: 30, price_minor: 0, currency: "NIO" } }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("price_minor" => 0, "currency" => "NIO") }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} lee el catálogo pero no lo gestiona" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(service_count).to eq(0)
          end
        end
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }

        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(service_count).to eq(0)
        end
      end

      response "422", "un servicio en USD en una empresa con NIO (`currency: mismatch`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: "Limpieza", duration_minutes: 45, price_minor: 4_000, currency: "USD" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "currency", "code" => "mismatch"))
          expect(service_count).to eq(0)
        end
      end

      response "422", "un precio negativo (`price_minor: greater_than_or_equal_to`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: "Corte", duration_minutes: 30, price_minor: -1 } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "price_minor", "code" => "greater_than_or_equal_to"))
          expect(service_count).to eq(0)
        end
      end

      response "422", "sin nombre ni duración" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { name: " ", price_minor: 100 } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "name", "code" => "blank"), a_hash_including("field" => "duration_minutes"))
        end
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/services/{id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del servicio"

    let!(:service) { service_in(world.company_a, name: "Corte", price_minor: 20_000) }
    let(:id) { service.id }
    let(:foreign) { service_in(world.company_b, name: "Foráneo") }

    get "Obtiene un servicio" do
      tags "Servicios"
      description "Exige `appointments.service.read`. Un servicio de otra empresa responde 404. Un archivado se puede ver, con `archived_at`."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el servicio" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => service.id, "name" => "Corte", "price_minor" => 20_000) }
      end

      response "200", "un servicio archivado se puede ver" do
        let!(:signed_in) { sign_in(manager) }
        let!(:service) { service_in(world.company_a, archived_at: Time.current) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]["archived_at"]).to be_present }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "un rol de organización no tiene permiso" do
        let!(:signed_in) { sign_in(user_with_role("org_owner", world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "un servicio de la empresa B desde la ruta de la empresa A" do
        let!(:signed_in) { sign_in(manager) }
        let(:id) { foreign.id }
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

    patch "Edita un servicio" do
      tags "Servicios"
      description "Exige `appointments.service.manage`. Solo cambia los campos enviados; la empresa y el archivado no se editan por aquí."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ServicePatch" }

      let(:body) { { price_minor: 25_000, buffer_before_minutes: 10 } }

      response "200", "el servicio editado" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("name" => "Corte", "price_minor" => 25_000, "buffer_before_minutes" => 10)
          expect(audit_events("service.updated").map(&:auditable_id)).to eq([ service.id ])
        end
      end

      response "403", "el branch_manager no gestiona el catálogo y el servicio queda intacto" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored(service.id).price_minor).to eq(20_000)
        end
      end

      response "404", "un servicio de otra empresa no se edita y queda intacto" do
        let!(:signed_in) { sign_in(manager) }
        let(:id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(stored(foreign.id).price_minor).to eq(20_000)
        end
      end

      response "422", "un servicio archivado no se edita (`base: archived`) y queda intacto" do
        let!(:signed_in) { sign_in(manager) }
        let!(:archived_service) { service_in(world.company_a, name: "Viejo", price_minor: 20_000, archived_at: Time.current) }
        let(:id) { archived_service.id }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived"))
          expect(stored(archived_service.id).price_minor).to eq(20_000)
        end
      end

      response "422", "cambiar la moneda a una que no es la de la empresa" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { currency: "USD" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "currency", "code" => "mismatch"))
          expect(stored(service.id).currency).to eq("NIO")
        end
      end
    end

    delete "Archiva un servicio" do
      tags "Servicios"
      description "Exige `appointments.service.manage`. No borra la fila: fija `archived_at` y lo saca del catálogo. Repetirlo no cambia nada."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "archivado: la fila sigue y ya no está en el catálogo" do
        let!(:signed_in) { sign_in(manager) }

        run_test! do |deleted|
          expect(deleted.body).to be_empty
          expect(stored(service.id).archived_at).to be_present
          expect(audit_events("service.archived").map(&:auditable_id)).to eq([ service.id ])
          get "/api/v1/organizations/#{organization_id}/companies/#{company_id}/appointments/services"
          expect(response.parsed_body["data"]).to be_empty
        end
      end

      response "204", "archivarlo otra vez no cambia la fecha ni duplica la auditoría" do
        let!(:signed_in) { sign_in(manager) }
        let!(:service) { service_in(world.company_a, archived_at: Time.zone.local(2026, 1, 1)) }

        run_test! do
          expect(stored(service.id).archived_at).to eq(Time.zone.local(2026, 1, 1))
          expect(audit_events("service.archived")).to be_empty
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      %w[branch_manager receptionist professional].each do |role|
        response "403", "el #{role} no puede archivar y el servicio sigue en el catálogo" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(stored(service.id).archived_at).to be_nil
          end
        end
      end

      response "404", "un servicio de otra empresa no se archiva" do
        let!(:signed_in) { sign_in(manager) }
        let(:id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(stored(foreign.id).archived_at).to be_nil
        end
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
