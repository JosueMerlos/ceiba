require "swagger_helper"

# Customers of a company, managed from the branch the staff acts from. The customer is a COMPANY record: the listing shows
# every customer of the branch's company. The phone, email and notes are returned only to holders of
# `platform.customer.read`.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: clientes" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:unknown_id) { "0198f0a0-0000-7000-8000-000000000000" }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }

  # Schemas are read when the file loads, so they are plain locals rather than `let`s.
  list_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/Customer" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }
  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Customer" } } }

  def customer_in(company, **attributes) = create_in(world.organization, :customer, company:, **attributes)
  def stored(id) = with_tenant(world.organization) { Customers::Customer.find(id) }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/customers" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true,
              description: "Sucursal desde la que se actúa; los clientes son de su empresa"

    get "Lista los clientes activos de la empresa de la sucursal" do
      tags "Clientes"
      description "Exige `platform.customer.read` en la sucursal. Paginado por cursor. Filtros: `phone` (exacto, en cualquier formato) y " \
                  "`name_prefix` (prefijo del nombre, sin distinguir mayúsculas). Los archivados no aparecen."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :phone, in: :query, schema: { type: :string }, required: false
      parameter name: :name_prefix, in: :query, schema: { type: :string }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      let!(:ana) { customer_in(world.company_a, full_name: "Ana López", phone_e164: "8888-7777", email: "ana@example.com", notes: "prefiere tardes") }
      let!(:bruno) { customer_in(world.company_a, full_name: "Bruno Díaz", phone_e164: "8888-6666") }
      let!(:archived) { customer_in(world.company_a, full_name: "Ana Archivada", phone_e164: "8888-5555", archived_at: Time.current) }
      let!(:foreign) { customer_in(world.company_b, full_name: "Ana Foránea", phone_e164: "8888-7777") }

      response "200", "los clientes activos de la empresa" do
        let!(:signed_in) { sign_in(receptionist) }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id, bruno.id ])
          expect(response.parsed_body["data"].first).to include("full_name" => "Ana López", "phone_e164" => "+50588887777", "email" => "ana@example.com", "notes" => "prefiere tardes")
        end
      end

      response "200", "filtrado por teléfono en otro formato (solo el de la empresa de la ruta)" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:phone) { "8888 7777" }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id ]) }
      end

      response "200", "filtrado por prefijo del nombre" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:name_prefix) { "BRU" }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ bruno.id ]) }
      end

      response "200", "un comodín en `name_prefix` no devuelve todo" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:name_prefix) { "%" }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"]).to be_empty }
      end

      response "200", "paginado por cursor" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:limit) { 1 }
        schema list_schema

        run_test! do |response|
          expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id ])
          expect(response.parsed_body["page"]["has_more"]).to be(true)
        end
      end

      response "200", "el branch_manager de la sucursal lista" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].size).to eq(2) }
      end

      response "200", "el company_manager lista desde cualquier sucursal de su empresa (regla hacia abajo)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:branch_id) { world.branch_a2.id }
        schema list_schema

        run_test! { |response| expect(response.parsed_body["data"].pluck("id")).to eq([ ana.id, bruno.id ]) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "el profesional no tiene permiso sobre clientes (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "403", "org_admin no tiene permiso de clientes (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "una sucursal de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "la empresa de otro grupo de sucursales: el recepcionista de A no ve la empresa B" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:company_id) { world.company_b.id }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "una sucursal hermana a la que el recepcionista no pertenece" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:branch_id) { world.branch_a2.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end

    post "Crea un cliente" do
      tags "Clientes"
      description "Exige `platform.customer.create`. El teléfono se guarda en E.164 con el país de la organización. Si la empresa ya tiene un " \
                  "cliente ACTIVO con ese teléfono responde 422 (`phone_e164: taken`); si lo tiene ARCHIVADO, lo restaura con ese mismo id: el nombre sale de la " \
                  "petición y el correo y las notas quedan vacíos salvo que se envíen (el número pudo pasar a otra persona). Acepta `Idempotency-Key`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter "$ref" => "#/components/parameters/IdempotencyKey"
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/CustomerInput" }

      let(:body) { { full_name: "Ana López", phone_e164: "8888-7777", email: "Ana@Example.com", notes: "prefiere tardes" } }

      response "201", "el cliente creado, con el teléfono en E.164" do
        let!(:signed_in) { sign_in(receptionist) }
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("full_name" => "Ana López", "phone_e164" => "+50588887777", "email" => "ana@example.com", "notes" => "prefiere tardes", "archived_at" => nil)
          expect(stored(data["id"]).company_id).to eq(world.company_a.id)
          created = audit_events("customer.created")
          expect(created.map(&:auditable_id)).to eq([ data["id"] ])
          expect(created.first.attributes.slice("before", "after", "metadata").to_json).not_to match(/Ana|8888|example|tardes/)
        end
      end

      response "201", "con un cliente archivado del mismo teléfono lo restaura (no duplica)" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:archived) { customer_in(world.company_a, full_name: "Nombre Viejo", phone_e164: "8888-7777", email: "viejo@example.com", notes: "nota vieja", archived_at: 3.days.ago) }
        let(:body) { { full_name: "Ana López", phone_e164: "8888-7777" } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("id" => archived.id, "full_name" => "Ana López", "email" => nil, "notes" => nil, "archived_at" => nil)
          expect(with_tenant(world.organization) { Customers::Customer.count }).to eq(1)
          expect(audit_events("customer.restored").map(&:auditable_id)).to eq([ archived.id ])
          expect(audit_events("customer.created")).to be_empty
        end
      end

      response "201", "el mismo teléfono en la otra empresa del grupo es otro cliente" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:foreign) { customer_in(world.company_b, phone_e164: "8888-7777") }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]["id"]).not_to eq(foreign.id)
          expect(with_tenant(world.organization) { Customers::Customer.pluck(:company_id) }).to contain_exactly(world.company_a.id, world.company_b.id)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "el profesional no puede crear clientes" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(with_tenant(world.organization) { Customers::Customer.count }).to eq(0)
        end
      end

      response "404", "una sucursal de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(with_tenant(world.organization) { Customers::Customer.count }).to eq(0)
        end
      end

      response "422", "un teléfono inválido (`phone_e164: invalid`)" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:body) { { full_name: "Ana López", phone_e164: "123" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "phone_e164", "code" => "invalid"))
          expect(response.body).not_to include("123")
        end
      end

      response "422", "un teléfono ya usado por un cliente activo de la empresa (`phone_e164: taken`)" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:existing) { customer_in(world.company_a, phone_e164: "8888-7777") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "phone_e164", "code" => "taken"))
          expect(with_tenant(world.organization) { Customers::Customer.count }).to eq(1)
        end
      end

      response "422", "sin nombre (`full_name: blank`)" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:body) { { full_name: " ", phone_e164: "8888-7777" } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "full_name", "code" => "blank")) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/customers/{id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del cliente"

    let!(:customer) { customer_in(world.company_a, full_name: "Ana López", phone_e164: "8888-7777") }
    let(:id) { customer.id }
    let(:foreign) { customer_in(world.company_b, full_name: "Ana Foránea", phone_e164: "8888-7777") }

    get "Obtiene un cliente" do
      tags "Clientes"
      description "Exige `platform.customer.read`. Un cliente de otra empresa responde 404."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el cliente" do
        let!(:signed_in) { sign_in(receptionist) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]).to include("id" => customer.id, "full_name" => "Ana López", "phone_e164" => "+50588887777") }
      end

      response "200", "un cliente archivado se puede ver, con su fecha de archivado" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:customer) { customer_in(world.company_a, archived_at: Time.current) }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"]["archived_at"]).to be_present }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el profesional no tiene permiso" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "un cliente de la empresa B desde la ruta de la empresa A (mismo teléfono, otro cliente)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "404", "un id que no existe" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:id) { unknown_id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end

    patch "Edita un cliente" do
      tags "Clientes"
      description "Exige `platform.customer.update`. Solo cambia los campos enviados; la empresa y el archivado no se editan por aquí. " \
                  "Un cliente archivado no admite cambios (422 `base: archived`): solo se recupera con el alta (restaurar)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/CustomerPatch" }

      let(:body) { { full_name: "Ana María López", phone_e164: "8888 6666", notes: "nueva nota" } }

      response "200", "el cliente editado" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("full_name" => "Ana María López", "phone_e164" => "+50588886666", "notes" => "nueva nota")
          expect(stored(customer.id).phone_e164).to eq("+50588886666")
          events = audit_events("customer.updated")
          expect(events.map(&:metadata)).to eq([ { "changed" => %w[full_name phone_e164 notes] } ])
          expect(events.first.attributes.slice("before", "after", "metadata").to_json).not_to match(/Ana|8888|nota/)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "422", "un cliente archivado no admite cambios (`base: archived`)" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:customer) { customer_in(world.company_a, full_name: "Ana Archivada", phone_e164: "8888-7777", archived_at: 2.days.ago) }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived"))
          expect(stored(customer.id).full_name).to eq("Ana Archivada")
          expect(audit_events("customer.updated")).to be_empty
        end
      end

      response "403", "el profesional no puede editar, ni siquiera un cliente archivado" do
        let!(:customer) { customer_in(world.company_a, phone_e164: "8888-7777", archived_at: 2.days.ago) }
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "403", "el profesional no puede editar" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "un cliente de otra empresa no se edita y queda intacto" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:id) { foreign.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(stored(foreign.id).full_name).to eq("Ana Foránea")
        end
      end

      response "422", "el teléfono de otro cliente de la empresa (`phone_e164: taken`)" do
        let!(:signed_in) { sign_in(receptionist) }
        let!(:other) { customer_in(world.company_a, phone_e164: "8888-6666") }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "phone_e164", "code" => "taken"))
          expect(stored(customer.id).phone_e164).to eq("+50588887777")
        end
      end
    end

    delete "Archiva un cliente" do
      tags "Clientes"
      description "Exige `platform.customer.archive`. No borra la fila: fija `archived_at` y lo saca del listado. Repetirlo no cambia nada."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "archivado" do
        let!(:signed_in) { sign_in(receptionist) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(stored(customer.id).archived_at).to be_present
          expect(audit_events("customer.archived").map(&:auditable_id)).to eq([ customer.id ])
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el profesional no puede archivar" do
        let!(:signed_in) { sign_in(user_with_role("professional", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored(customer.id).archived_at).to be_nil
        end
      end

      response "404", "un cliente de otra empresa no se archiva" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
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
