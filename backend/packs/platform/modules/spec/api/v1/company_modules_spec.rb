require "swagger_helper"

# Activar/desactivar un módulo de una empresa y escribir sus settings (M0.09). Exige `platform.company_module.manage` (org_owner y
# org_admin, matriz de 04). Criterio 6: settings inválidos => 422 con el detalle por campo. La UI llega con M4.01.
# rswag exige que el `let` se llame igual que el parámetro de cabecera (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: módulos de una empresa" do
  include_context "con el módulo sample sincronizado"

  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:key) { "sample" }
  let(:admin) { user_with_role("org_admin", world) }
  # rswag exige que el `let` se llame igual que el parámetro de cabecera.
  let("X-CSRF-Token") { signed_in.csrf_token }

  def enable_sample = with_tenant(world.organization) { Modules::Enable.call(company: world.company_a, key: "sample") }

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/modules/{key}" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :key, in: :path, schema: { type: :string }, required: true, description: "Key estable del módulo (p. ej. appointments)"

    put "Activa o desactiva un módulo en la empresa" do
      tags "Módulos"
      description "Idempotente: repetir no cambia nada (`changed: false`). Activar exige que los módulos de `requires` estén activos; " \
                  "desactivar no borra datos y no deja si otro módulo activo lo requiere. Exige `platform.company_module.manage`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[enabled], additionalProperties: false, properties: { enabled: { type: :boolean } } }

      response "200", "el estado del módulo tras la llamada" do
        let!(:signed_in) { sign_in(admin) }
        let(:body) { { enabled: true } }

        schema "$ref" => "#/components/schemas/ModuleActivation"

        run_test! do |response|
          expect(response.parsed_body["data"]).to eq("key" => "sample", "enabled" => true, "changed" => true)
          expect(with_tenant(world.organization) { Modules.enabled?(world.company_a, "sample") }).to be(true)
        end
      end

      response "200", "desactivar (y repetir no cambia nada)" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:body) { { enabled: false } }

        schema "$ref" => "#/components/schemas/ModuleActivation"

        run_test! { |response| expect(response.parsed_body["data"]).to eq("key" => "sample", "enabled" => false, "changed" => true) }
      end

      response "400", "falta `enabled`" do
        let!(:signed_in) { sign_in(admin) }
        let(:body) { {} }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("request.invalid") }
      end

      response "401", "sin sesión válida" do
        let("X-CSRF-Token") { "sin-sesion" }
        let(:body) { { enabled: true } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "sin `platform.company_module.manage` (p. ej. company_manager)" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)) }
        let(:body) { { enabled: true } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "módulo inexistente (`modules.unknown_module`) o empresa no visible" do
        let!(:signed_in) { sign_in(admin) }
        let(:key) { "fantasma" }
        let(:body) { { enabled: true } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("modules.unknown_module") }
      end

      response "409", "faltan módulos requeridos (`modules.requirements_not_met`) o lo requiere otro activo (`modules.required_by_others`)" do
        let!(:signed_in) { sign_in(admin) }
        let(:key) { "sample_addon" }
        let(:body) { { enabled: true } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body).to include("code" => "modules.requirements_not_met", "detail" => include("sample")) }
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/modules/{key}/settings" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :key, in: :path, schema: { type: :string }, required: true

    patch "Cambia los settings del módulo (empresa o sucursal)" do
      tags "Módulos"
      description "Cambia SOLO las claves enviadas (un valor `null` quita el override), a nivel empresa. Cada valor se valida contra el " \
                  "JSON Schema del módulo: un valor inválido da 422 con el detalle por campo. Exige el módulo activo y " \
                  "`platform.company_module.manage`."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[settings], additionalProperties: false, properties: { settings: { type: :object } } }

      response "200", "los settings resueltos de ese nivel" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:body) { { settings: { max_advance_days: 30 } } }

        schema "$ref" => "#/components/schemas/ModuleSettings"

        run_test! { |response| expect(response.parsed_body["data"]).to include("key" => "sample", "settings" => include("max_advance_days" => 30, "min_lead_time_minutes" => 120)) }
      end

      response "401", "sin sesión válida" do
        let("X-CSRF-Token") { "sin-sesion" }
        let(:body) { { settings: {} } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "sin `platform.company_module.manage`" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_a)).tap { enable_sample } }
        let(:body) { { settings: { max_advance_days: 30 } } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "409", "el módulo no está activo en la empresa (`modules.not_enabled`)" do
        let!(:signed_in) { sign_in(admin) }
        let(:body) { { settings: { max_advance_days: 30 } } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("modules.not_enabled") }
      end

      response "422", "criterio 6: valores inválidos según el esquema, con el detalle por campo" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:body) { { settings: { min_lead_time_minutes: -5, public_booking_enabled: "si" } } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body).to include("code" => "modules.invalid_settings", "status" => 422)
          expect(response.parsed_body["errors"]).to contain_exactly(
            { "field" => "min_lead_time_minutes", "code" => "minimum", "message" => "es menor que el mínimo permitido" },
            { "field" => "public_booking_enabled", "code" => "type", "message" => "no tiene el tipo esperado" }
          )
        end
      end
    end
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branches/{branch_id}/modules/{key}/settings" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :branch_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :key, in: :path, schema: { type: :string }, required: true

    patch "Cambia los settings del módulo a nivel sucursal" do
      tags "Módulos"
      description "Igual que a nivel empresa, pero solo para las claves que el esquema permite sobrescribir en una sucursal; las demás dan 422 " \
                  "(`not_allowed_at_level`). La sucursal debe ser de la empresa de la ruta y visible para el usuario (404 si no)."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[settings], additionalProperties: false, properties: { settings: { type: :object } } }

      let(:branch_id) { world.branch_a1.id }

      response "200", "los settings resueltos de la sucursal (criterio 5)" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:body) { { settings: { min_lead_time_minutes: 60 } } }

        schema "$ref" => "#/components/schemas/ModuleSettings"

        run_test! do |response|
          expect(response.parsed_body.dig("data", "settings", "min_lead_time_minutes")).to eq(60)
          expect(with_tenant(world.organization) { Modules.settings_for("sample", company: world.company_a)["min_lead_time_minutes"] }).to eq(120)
        end
      end

      response "403", "sin `platform.company_module.manage` en la sucursal" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)).tap { enable_sample } }
        let(:body) { { settings: { min_lead_time_minutes: 60 } } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "la sucursal no es de la empresa o no existe" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:branch_id) { world.branch_b1.id }
        let(:body) { { settings: { min_lead_time_minutes: 60 } } }

        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      response "422", "una clave que el esquema solo permite a nivel empresa" do
        let!(:signed_in) { sign_in(admin).tap { enable_sample } }
        let(:body) { { settings: { cancellation_window_hours: 2 } } }

        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! { |response| expect(response.parsed_body["errors"]).to eq([ { "field" => "cancellation_window_hours", "code" => "not_allowed_at_level", "message" => "no se puede sobrescribir a nivel sucursal" } ]) }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
