require "swagger_helper"

# A branch's override of a company service. Authorization is by EFFECTIVE CHANGE against the row as it is now, at the
# branch's scope: changing the duration needs `appointments.service.override_duration`, changing the price needs
# `appointments.service.override_price`; if the change includes something the user may not touch, the whole request is a
# 403 and nothing is applied. PUT merges (only the sent fields change; null clears a field).
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: overrides de servicio por sucursal" do
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
  let!(:service) { create_in(world.organization, :service, company: world.company_a, price_minor: 20_000, duration_minutes: 30) }
  let(:service_id) { service.id }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/ServiceOverride" } } }

  def override_in(service, branch, **attributes) = create_in(world.organization, :branch_service_override, service:, branch:, **attributes)
  def stored_override = with_tenant(world.organization) { Appointments::BranchServiceOverride.order(:created_at).last }
  def override_count = with_tenant(world.organization) { Appointments::BranchServiceOverride.count }
  def audit_events(action) = with_tenant(world.organization) { Audit::Event.where(action:).to_a }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/appointments/branches/{branch_id}/services/{service_id}/override" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "Sucursal que tiene el override"
    parameter name: :service_id, in: :path, schema: { type: :string, format: :uuid }, required: true, description: "ID del servicio de la empresa"

    put "Fija o cambia el override de un servicio en una sucursal" do
      tags "Servicios"
      description "Crea el override o lo cambia. MEZCLA: solo cambian los campos enviados, lo que no viene se conserva y un `null` explícito " \
                  "quita ese valor. El resultado debe conservar duración o precio (si no, 422; para quitarlo todo, `DELETE`). " \
                  "Se autoriza por CAMBIO EFECTIVO respecto de la fila actual en el alcance de la sucursal: cambiar la duración exige " \
                  "`appointments.service.override_duration` y cambiar el precio `appointments.service.override_price`. Si el cambio incluye algo " \
                  "que el usuario no puede tocar, responde 403 para TODA la petición y no se aplica nada. Reenviar el valor que ya tiene no es un cambio. " \
                  "El override hereda la moneda del servicio."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { "$ref" => "#/components/schemas/ServiceOverrideInput" }

      let(:body) { { duration_minutes: 45, price_minor: 25_000 } }

      response "200", "el company_manager fija duración y precio" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("branch_id" => branch_id, "service_id" => service_id, "duration_minutes" => 45, "price_minor" => 25_000, "currency" => "NIO")
          expect(stored_override).to have_attributes(branch_id:, service_id:, company_id: world.company_a.id, duration_minutes: 45, price_minor: 25_000)
          expect(audit_events("service_override.set").size).to eq(1)
        end
      end

      response "200", "el branch_manager fija solo la duración (permitido)" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:body) { { duration_minutes: 45 } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("duration_minutes" => 45, "price_minor" => nil)
          expect(stored_override).to have_attributes(duration_minutes: 45, price_minor: nil)
        end
      end

      response "200", "el company_manager cambia solo el precio de un override existente y la duración se conserva (mezcla)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { price_minor: 27_000 } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("id" => existing.id, "duration_minutes" => 45, "price_minor" => 27_000)
          expect(override_count).to eq(1)
        end
      end

      response "200", "el company_manager quita el precio con null y se conserva la duración" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { price_minor: nil } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("duration_minutes" => 45, "price_minor" => nil)
          expect(stored_override.id).to eq(existing.id)
        end
      end

      response "200", "el branch_manager manda solo la duración sobre un override con precio del company_manager: el precio queda intacto" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { duration_minutes: 50 } }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to include("duration_minutes" => 50, "price_minor" => 25_000)
          expect(stored_override).to have_attributes(duration_minutes: 50, price_minor: 25_000)
        end
      end

      response "200", "el branch_manager reenvía el MISMO precio que ya tiene: no es un cambio, solo cambia la duración" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { duration_minutes: 50, price_minor: 25_000 } }
        schema single_schema

        run_test! { expect(stored_override).to have_attributes(duration_minutes: 50, price_minor: 25_000) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el branch_manager intenta un override de precio (`access.forbidden`) y no se crea nada" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:body) { { price_minor: 25_000 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(override_count).to eq(0)
          expect(audit_events("service_override.set")).to be_empty
        end
      end

      response "403", "una petición MIXTA (duración permitida y precio no) es 403 para toda la petición: no se aplica ni la duración" do
        let!(:signed_in) { sign_in(branch_manager) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(0) }
      end

      response "403", "el branch_manager no puede borrar con null el precio que fijó el company_manager: el precio sigue intacto" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { duration_minutes: 40, price_minor: nil } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do
          expect(stored_override).to have_attributes(id: existing.id, duration_minutes: 45, price_minor: 25_000)
          expect(audit_events("service_override.set")).to be_empty
        end
      end

      response "403", "el branch_manager no puede cambiar el precio de un override existente" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        let(:body) { { price_minor: 1 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(stored_override.price_minor).to eq(25_000) }
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} lee el catálogo pero no puede tocar overrides" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          let(:body) { { duration_minutes: 45 } }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! do |response|
            expect(response.parsed_body["code"]).to eq("access.forbidden")
            expect(override_count).to eq(0)
          end
        end
      end

      response "403", "una petición vacía sin permisos de override tampoco pasa (no revela nada)" do
        let!(:signed_in) { sign_in(user_with_role("receptionist", world, branch: world.branch_a1)) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45) }
        let(:body) { {} }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "una sucursal hermana a la que el branch_manager no pertenece" do
        let!(:signed_in) { sign_in(branch_manager) }
        let(:branch_id) { world.branch_a2.id }
        let(:body) { { duration_minutes: 45 } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(0) }
      end

      response "404", "una sucursal de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:branch_id) { world.branch_b1.id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(0) }
      end

      response "404", "un servicio de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:service_id) { create_in(world.organization, :service, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(override_count).to eq(0)
        end
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }

        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(0) }
      end

      response "422", "sin duración ni precio (`validation.failed`)" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { {} }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "empty"))
          expect(override_count).to eq(0)
        end
      end

      response "422", "un servicio archivado no admite overrides (`base: archived`) y no se crea nada" do
        let!(:signed_in) { sign_in(manager) }
        let!(:archived_service) { create_in(world.organization, :service, company: world.company_a, archived_at: Time.current) }
        let(:service_id) { archived_service.id }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "base", "code" => "archived"))
          expect(override_count).to eq(0)
        end
      end

      response "422", "una duración no positiva" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { duration_minutes: 0 } }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["errors"]).to include(a_hash_including("field" => "duration_minutes", "code" => "greater_than"))
          expect(override_count).to eq(0)
        end
      end

      response "400", "un valor que no es entero" do
        let!(:signed_in) { sign_in(manager) }
        let(:body) { { price_minor: "gratis" } }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(0) }
      end
    end

    delete "Quita el override de un servicio en una sucursal" do
      tags "Servicios"
      description "Exige `appointments.service.override_price` si el override tiene precio y `appointments.service.override_duration` si tiene " \
                  "duración (quitarlo es cambiar ambos valores). La sucursal vuelve a usar los del servicio. Sin override responde 404."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "el company_manager quita un override con duración y precio" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }

        run_test! do |response|
          expect(response.body).to be_empty
          expect(override_count).to eq(0)
          expect(audit_events("service_override.removed").map(&:auditable_id)).to eq([ existing.id ])
        end
      end

      response "204", "el branch_manager quita un override que solo tiene duración" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45) }

        run_test! { expect(override_count).to eq(0) }
      end

      response "204", "quitar el override de una sucursal no toca el de otra" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45) }
        let!(:sibling) { override_in(service, world.branch_a2, duration_minutes: 50) }

        run_test! { expect(with_tenant(world.organization) { Appointments::BranchServiceOverride.pluck(:id) }).to eq([ sibling.id ]) }
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "403", "el branch_manager no puede quitar un override con precio: el precio sigue intacto" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45, price_minor: 25_000) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(stored_override).to have_attributes(id: existing.id, price_minor: 25_000, duration_minutes: 45)
          expect(audit_events("service_override.removed")).to be_empty
        end
      end

      response "403", "el branch_manager no puede quitar un override que solo tiene precio" do
        let!(:signed_in) { sign_in(branch_manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: nil, price_minor: 25_000) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(1) }
      end

      %w[receptionist professional].each do |role|
        response "403", "el #{role} no puede quitar overrides" do
          let!(:signed_in) { sign_in(user_with_role(role, world, branch: world.branch_a1)) }
          let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45) }
          schema "$ref" => "#/components/schemas/Problem"

          run_test! { expect(override_count).to eq(1) }
        end
      end

      response "404", "sin override en esa sucursal" do
        let!(:signed_in) { sign_in(manager) }
        let!(:sibling) { override_in(service, world.branch_a2, duration_minutes: 50) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("resource.not_found")
          expect(override_count).to eq(1)
        end
      end

      response "404", "un servicio de otra empresa en la ruta" do
        let!(:signed_in) { sign_in(manager) }
        let(:service_id) { create_in(world.organization, :service, company: world.company_b).id }
        schema "$ref" => "#/components/schemas/Problem"

        run_test!
      end

      response "404", "con el módulo de citas desactivado en la empresa (el gate)" do
        let!(:signed_in) { sign_in(manager) }
        let!(:existing) { override_in(service, world.branch_a1, duration_minutes: 45) }

        let!(:module_disabled) { with_tenant(world.organization) { Modules::Disable.call(company: world.company_a, key: "appointments") } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { expect(override_count).to eq(1) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
