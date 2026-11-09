require "rails_helper"

# Criterio 2 de M0.09: una ruta de un módulo inactivo en la empresa responde 404, igual que un recurso inexistente (no se revela
# nada); con el módulo activo se aplica la autorización de siempre. Criterio 8 por HTTP: desactivar y reactivar.
RSpec.describe "Concern RequiresModule" do
  include_context "con rutas de sample"
  include_context "con el módulo sample sincronizado"

  let(:world) { build_access_world }
  let(:company) { world.company_a }
  let(:manager) { user_with_role("company_manager", world, company:) }

  def enable(target = company) = with_tenant(world.organization) { Modules::Enable.call(company: target, key: "sample") }
  def disable(target = company) = with_tenant(world.organization) { Modules::Disable.call(company: target, key: "sample") }
  def get_things(target = company) = get(sample_things_path(target))

  describe "con el módulo inactivo (criterio 2)" do
    before { sign_in(manager) }

    it "responde 404 problem+json resource.not_found, como un recurso inexistente" do
      get_things

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/problem+json")
      expect(response.parsed_body).to include("code" => "resource.not_found", "status" => 404)
    end

    it "el 404 es idéntico al de una empresa que no existe (no revela que el módulo existe)" do
      get_things
      inactive = response.parsed_body.except("instance", "request_id")
      get "/api/v1/organizations/#{world.organization.id}/companies/#{SampleModule::UNKNOWN_ID}/sample/things"

      expect(response.parsed_body.except("instance", "request_id")).to eq(inactive)
    end

    it "responde 404 aunque el usuario tenga todos los permisos del módulo (el módulo se verifica antes que la autorización)" do
      sign_in(user_with_role("org_admin", world))
      get_things

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "con el módulo activo" do
    before { enable }

    it "deja pasar al que tiene el permiso" do
      sign_in(manager)
      get_things

      expect(response).to have_http_status(:ok)
    end

    it "sigue aplicando la autorización: sin el permiso del módulo, 403" do
      sign_in(user_with_role("org_owner", world))
      get_things

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("access.forbidden")
    end

    it "el policy_scope (reach filtrado por módulo activo) lista lo de la empresa del contexto" do
      sign_in(manager)
      get_things

      expect(response.parsed_body["data"]).to contain_exactly(world.branch_a1.id, world.branch_a2.id)
    end

    it "activo en una empresa, inactivo en la otra: 404 en la otra" do
      sign_in(user_with_role("org_admin", world))
      get_things(world.company_b)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "activar, desactivar y reactivar (criterio 8, por HTTP)" do
    before { sign_in(manager) }

    it "desactivado vuelve a 404 y reactivado recupera el acceso" do
      enable
      get_things
      expect(response).to have_http_status(:ok)

      disable
      get_things
      expect(response).to have_http_status(:not_found)

      enable
      get_things
      expect(response).to have_http_status(:ok)
    end
  end

  describe "orden de las verificaciones" do
    it "sin sesión: 401 (la autenticación va primero)" do
      get_things

      expect(response).to have_http_status(:unauthorized)
    end

    it "un usuario que no es miembro de la organización: 404, también con el módulo activo" do
      enable
      sign_in(create(:user))
      get_things

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "una sola consulta de módulos por request (sin N+1)" do
    it "RequiresModule y el permiso del módulo comparten la misma consulta a company_modules" do
      enable
      sign_in(manager)
      statements = []
      callback = ->(*, payload) { statements << payload[:sql] if payload[:sql].include?("company_modules") }

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get_things }

      expect(response).to have_http_status(:ok)
      expect(statements.size).to eq(1)
    end
  end

  describe "la declaración" do
    it "exige una key de un módulo que exista" do
      expect { Class.new(Api::BaseController) { include Modules::RequiresModule; requires_module :fantasma } }.to raise_error(Modules::UnknownModule)
    end

    it "un controlador que incluye el concern y no declara el módulo falla cerrado (bug del código, no un acceso libre)" do
      controller = Class.new(Api::BaseController) { include Modules::RequiresModule }

      expect(controller.required_module).to be_nil
      expect { controller.new.send(:ensure_required_module_enabled!) }.to raise_error(Modules::Error, /requires_module/)
    end
  end
end
