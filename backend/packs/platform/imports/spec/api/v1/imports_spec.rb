require "swagger_helper"

# CSV imports of a company's data, uploaded from the branch the staff acts from. The file travels base64-encoded inside
# the JSON body (mutations only accept application/json). A batch is previewed (every row validated, none applied) and
# then confirmed; a job applies it in chunks.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: importaciones" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:branch_id) { world.branch_a1.id }
  let(:manager) { user_with_role("branch_manager", world, branch: world.branch_a1) }
  let(:receptionist) { user_with_role("receptionist", world, branch: world.branch_a1) }
  let("X-CSRF-Token") { signed_in.csrf_token }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/ImportBatch" } } }
  rows_schema = {
    type: :object, required: %w[data page], additionalProperties: false, properties: {
      data: { type: :array, items: { "$ref" => "#/components/schemas/ImportRow" } },
      page: { "$ref" => "#/components/schemas/PageInfo" }
    }
  }

  def csv(count, invalid: []) = ([ "nombre;telefono;correo" ] + Array.new(count) { |index| invalid.include?(index) ? "Mal #{index};123;" : format("Persona %d;8800 %04d;", index, index + 1) }).join("\r\n")

  def encoded(text) = Base64.strict_encode64(text.encode("Windows-1252"))

  def upload(user, text = csv(3), kind: "customers")
    with_tenant(world.organization) do
      Imports::CreateBatch.call(kind:, bytes: text, company_id: world.company_a.id, branch_id: world.branch_a1.id, created_by_id: user.id)
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Sube un CSV y devuelve su previsualización" do
      tags "Importaciones"
      description "Lee el archivo (UTF-8, Windows-1252 o UTF-16; separador `;`, `,` o tabulador), valida cada fila y no aplica ninguna. " \
                  "Máximo 5000 filas y 5 MB. Clientes exige `platform.customer.import` y `platform.customer.read` en la sucursal; servicios " \
                  "`appointments.service.manage` y profesionales `appointments.professional.manage` en la empresa (con el módulo activo). " \
                  "La previsualización devuelve las primeras 20 filas con sus valores mientras el lote no se confirma."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, schema: { "$ref" => "#/components/schemas/ImportUpload" }

      response "201", "el lote previsualizado: 3 inválidas de 100 señaladas con su motivo" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kind: "customers", content_base64: encoded(csv(100, invalid: [ 10, 50, 99 ])) } }
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data.slice("kind", "status", "total_count", "ready_count", "rejected_count", "duplicate_modes", "columns"))
            .to eq("kind" => "customers", "status" => "previewed", "total_count" => 100, "ready_count" => 97, "rejected_count" => 3,
                   "duplicate_modes" => %w[skip update], "columns" => %w[nombre telefono correo notas])
          expect(data["preview"].size).to eq(20)
          expect(data["preview"].first).to eq("row_number" => 2, "status" => "ready", "error_codes" => {}, "values" => { "nombre" => "Persona 0", "telefono" => "8800 0001", "correo" => nil })
          expect(data["preview"][10]).to include("row_number" => 12, "status" => "rejected", "error_codes" => { "telefono" => "invalid" })
        end
      end

      response "422", "un archivo de 6000 filas se rechaza con un mensaje claro" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kind: "customers", content_base64: encoded(csv(6000)) } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body.slice("code", "detail"))
            .to eq("code" => "import.too_many_rows", "detail" => "El archivo tiene 6000 filas y el máximo es 5000: divídelo en varios archivos")
          expect(with_tenant(world.organization) { Imports::Batch.count }).to eq(0)
        end
      end

      response "422", "faltan columnas obligatorias" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { kind: "customers", content_base64: encoded("nombre\nAna\n") } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body.slice("code", "detail")).to eq("code" => "import.missing_columns", "detail" => "Faltan columnas obligatorias: telefono") }
      end

      response "403", "la recepción no importa clientes" do
        let!(:signed_in) { sign_in(receptionist) }
        let(:body) { { kind: "customers", content_base64: encoded(csv(1)) } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(with_tenant(world.organization) { Imports::Batch.count }).to eq(0) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports/{import_id}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :import_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Estado de un lote y sus primeras filas" do
      tags "Importaciones"
      description "Para seguir el avance tras confirmar. Los valores de las filas solo salen mientras el lote está en previsualización."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "el lote" do
        let!(:signed_in) { sign_in(manager) }
        let(:import_id) { upload(manager).id }
        schema single_schema

        run_test! { |response| expect(response.parsed_body["data"].slice("id", "status")).to eq("id" => import_id, "status" => "previewed") }
      end

      response "404", "un lote de otra empresa no existe para esta ruta" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_b)) }
        let(:company_id) { world.company_b.id }
        let(:branch_id) { create_in(world.organization, :branch, company: world.company_b).id }
        let(:import_id) { upload(manager).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports/{import_id}/rows" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :import_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Filas de un lote, por número de fila" do
      tags "Importaciones"
      description "Paginado por cursor. Filtro `status` (p. ej. `rejected` para el reporte de errores). Los códigos de error nunca llevan el valor."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: :status, in: :query, schema: { type: :string, enum: Imports::Row::STATUSES }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 100 }, required: false
      parameter name: :after, in: :query, schema: { type: :string }, required: false

      response "200", "las filas rechazadas" do
        let!(:signed_in) { sign_in(manager) }
        let(:import_id) { upload(manager, "nombre;telefono\nAna;8800 0001\nMal;12\n").id }
        let(:status) { "rejected" }
        schema rows_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to eq([ { "row_number" => 3, "status" => "rejected", "error_codes" => { "telefono" => "invalid" }, "values" => { "nombre" => "Mal", "telefono" => "12" } } ])
        end
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/imports/{import_id}/confirm" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :import_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    post "Confirma el lote y lo encola" do
      tags "Importaciones"
      description "`duplicate_mode`: `skip` deja intacto lo existente; `update` (solo clientes) escribe las celdas no vacías y restaura a los " \
                  "archivados. Las filas rechazadas no se importan. Un solo lote de cada tipo corre a la vez en la empresa."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, schema: { "$ref" => "#/components/schemas/ImportConfirmation" }

      response "202", "encolado" do
        let!(:signed_in) { sign_in(manager) }
        let(:import_id) { upload(manager).id }
        let(:body) { { duplicate_mode: "skip" } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"].slice("status", "duplicate_mode")).to eq("status" => "queued", "duplicate_mode" => "skip")
          expect(response.parsed_body["data"]["preview"].pluck("values").uniq).to eq([ nil ])
        end
      end

      response "409", "ya confirmado" do
        let!(:signed_in) { sign_in(manager) }
        let(:import_id) { upload(manager).tap { |batch| with_tenant(world.organization) { Imports::ConfirmBatch.call(batch:, duplicate_mode: "skip", confirmed_by_id: manager.id) } }.id }
        let(:body) { { duplicate_mode: "skip" } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("import.not_confirmable") }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
