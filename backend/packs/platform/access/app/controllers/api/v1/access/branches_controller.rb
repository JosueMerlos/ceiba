module Api
  module V1
    module Access
      # Branches of ONE company from the route, only those the principal can read (a company_manager sees all of the
      # company's; a branch_manager, their own).
      class BranchesController < ::Api::BaseController
        route_context branch: :id

        def index
          branches = ::Tenancy::Directory.branches.where(company_id: Current.context.company.id)
          authorize branches, :index?, policy_class: ::Access::BranchPolicy
          branches = policy_scope(branches, policy_scope_class: ::Access::BranchPolicy::Scope)
          render_page(branches, serializer: ::Tenancy::BranchSerializer)
        end

        # The company comes from the route, never the body; the permission is asked on the branch as it would be created (before
        # anything is written). The new branch has no weekly hours: it is closed until they are configured.
        def create
          authorize ::Tenancy::Directory.branches.new(company: Current.context.company), :create?, policy_class: ::Access::BranchPolicy
          branch = ::Tenancy::AddBranch.call(company: Current.context.company, **branch_params)
          render json: { data: ::Tenancy::BranchSerializer.new(branch).serializable_hash }, status: :created
        end

        def show
          branch = Current.context.branch
          authorize branch, :show?, policy_class: ::Access::BranchPolicy
          render json: { data: ::Tenancy::BranchSerializer.new(branch).serializable_hash }
        end

        private

        def branch_params = typed_params(name: String, time_zone: String, address: String, phone_e164: String)
      end
    end
  end
end
