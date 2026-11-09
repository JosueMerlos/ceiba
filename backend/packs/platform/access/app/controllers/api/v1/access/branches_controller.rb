module Api
  module V1
    module Access
      # Sucursales de UNA empresa de la ruta, solo las que el principal puede leer (un company_manager ve todas las de su
      # empresa; un branch_manager, la suya).
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
