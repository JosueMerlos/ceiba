# Rutas y controlador del módulo FICTICIO `sample` (M0.09), para los specs de RequiresModule y de la suite de cobertura de módulos.
# Se dibujan en el router solo para el grupo que las pide y se descartan al terminar (como spec/support/api_probes.rb): ningún
# endpoint de prueba existe en la aplicación real.
#
#   GET /api/v1/organizations/:organization_id/companies/:company_id/sample/things
#
# Es un controlador de verdad: hereda de Api::BaseController (autenticación y autorización obligatorias) y declara
# `requires_module :sample`, igual que un controlador de un pack de módulos.
module SampleModule
  UNKNOWN_ID = "0198f0a0-0000-7000-8000-000000000000".freeze

  # Se define bajo demanda para no cargar Api::BaseController en cada spec de la suite.
  def self.define_api!
    return if const_defined?(:ThingsController, false)

    const_set(:ThingPolicy, Class.new(Access::BasePolicy) do
      def index? = can?("sample.thing.read", company_scope)
      def show? = can?("sample.thing.read", company_scope)

      private

      def company_scope = Access::Scope.company(organization_id: Current.context.organization.id, company_id: Current.context.company.id)

      const_set(:Scope, Class.new(Access::BasePolicy::Scope) do
        def resolve
          reach = reach("sample.thing.read")
          reach.organization? ? scope : scope.where(company_id: reach.company_ids)
        end
      end)
    end)

    const_set(:ThingsController, Class.new(Api::BaseController) do
      include Modules::RequiresModule
      requires_module :sample

      # Las "cosas" de muestra son las sucursales de la empresa del contexto: lo justo para tener un listado con policy_scope.
      def index
        things = Tenancy::Directory.branches.where(company_id: Current.context.company.id)
        authorize things, :index?, policy_class: SampleModule::ThingPolicy
        render json: { data: policy_scope(things, policy_scope_class: SampleModule::ThingPolicy::Scope).pluck(:id) }
      end

      # Ruta de MIEMBRO (:id): un id desconocido da 404 por sí solo, por eso la suite de cobertura usa ids reales.
      def show
        thing = Tenancy::Directory.branches.where(company_id: Current.context.company.id).find(params[:id])
        authorize thing, :show?, policy_class: SampleModule::ThingPolicy
        render json: { data: thing.id }
      end
    end)

    # Ruta bajo branches/:branch_id: el resolvedor de rutas valida la sucursal ANTES del gate (404 si no existe).
    const_set(:BranchThingsController, Class.new(Api::BaseController) do
      include Modules::RequiresModule
      requires_module :sample

      route_context branch: :branch_id

      def index
        branch = Current.context.branch
        authorize branch, :show?, policy_class: SampleModule::ThingPolicy
        render json: { data: [ branch.id ] }
      end
    end)
  end

  module Helpers
    def sample_routes
      SampleModule.define_api!
      Rails.application.reload_routes_unless_loaded
      Rails.application.routes.disable_clear_and_finalize = true
      Rails.application.routes.draw do
        scope path: "api/v1/organizations/:organization_id/companies/:company_id/sample", controller: "sample_module/things" do
          get "things", action: :index
          get "things/:id", action: :show
        end
        scope path: "api/v1/organizations/:organization_id/companies/:company_id/branches/:branch_id/sample", controller: "sample_module/branch_things" do
          get "things", action: :index
        end
      end
    ensure
      Rails.application.routes.disable_clear_and_finalize = false
    end

    def sample_things_path(company) = "/api/v1/organizations/#{company.organization_id}/companies/#{company.id}/sample/things"
  end
end

RSpec.shared_context "con rutas de sample" do
  include SampleModule::Helpers

  before(:context) { sample_routes } # rubocop:disable RSpec/BeforeAfterAll -- dibujar rutas es caro y global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end
