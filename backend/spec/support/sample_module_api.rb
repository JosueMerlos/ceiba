# Routes and controller of the FICTITIOUS `sample` module, for the RequiresModule specs and the module coverage suite.
# They are drawn on the router only for the group that asks for them and dropped afterwards (like
# spec/support/api_probes.rb): no test endpoint exists in the real application.
#
#   GET /api/v1/organizations/:organization_id/companies/:company_id/sample/things
#
# It is a real controller: inherits Api::BaseController (mandatory authentication and authorization) and declares
# `requires_module :sample`, just like a controller in a modules pack.
module SampleModule
  UNKNOWN_ID = "0198f0a0-0000-7000-8000-000000000000".freeze

  # Defined on demand so Api::BaseController is not loaded in every spec of the suite.
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

      # The sample "things" are the context company's branches: just enough for a listing with policy_scope.
      def index
        things = Tenancy::Directory.branches.where(company_id: Current.context.company.id)
        authorize things, :index?, policy_class: SampleModule::ThingPolicy
        render json: { data: policy_scope(things, policy_scope_class: SampleModule::ThingPolicy::Scope).pluck(:id) }
      end

      # MEMBER route (:id): an unknown id gives 404 by itself, so the coverage suite uses real ids.
      def show
        thing = Tenancy::Directory.branches.where(company_id: Current.context.company.id).find(params[:id])
        authorize thing, :show?, policy_class: SampleModule::ThingPolicy
        render json: { data: thing.id }
      end
    end)

    # Route under branches/:branch_id: the route resolver validates the branch BEFORE the gate (404 if it does not exist).
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

  before(:context) { sample_routes } # rubocop:disable RSpec/BeforeAfterAll -- drawing routes is expensive and global
  after(:context) { Rails.application.reload_routes! } # rubocop:disable RSpec/BeforeAfterAll
end
