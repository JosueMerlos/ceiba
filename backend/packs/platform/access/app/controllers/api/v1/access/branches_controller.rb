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

        def show
          branch = Current.context.branch
          authorize branch, :show?, policy_class: ::Access::BranchPolicy
          render json: { data: ::Tenancy::BranchSerializer.new(branch).serializable_hash }
        end
      end
    end
  end
end
