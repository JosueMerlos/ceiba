module Api
  module V1
    module Access
      # Branches of ONE company from the route, only those the principal can read (a company_manager sees all of the
      # company's; a branch_manager, their own).
      class BranchesController < ::Api::BaseController
        include ::Idempotency::Idempotent

        route_context branch: :id

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        def index
          branches = ::Tenancy::Directory.branches.where(company_id: Current.context.company.id)
          authorize branches, :index?, policy_class: ::Access::BranchPolicy
          branches = policy_scope(branches, policy_scope_class: ::Access::BranchPolicy::Scope)
          render_page(branches, serializer: ::Tenancy::BranchSerializer)
        end

        # The company comes from the route, never the body. The new branch has no weekly hours: it is closed until they are
        # configured.
        def create
          branch = ::Access::CreateBranch.call(company: Current.context.company, attributes: branch_params)
          render json: { data: ::Tenancy::BranchSerializer.new(branch).serializable_hash }, status: :created
        end

        def show
          branch = Current.context.branch
          authorize branch, :show?, policy_class: ::Access::BranchPolicy
          render json: { data: ::Tenancy::BranchSerializer.new(branch).serializable_hash }
        end

        private

        # The permission is asked on the branch as it would be created, before anything is written.
        def authorize_creation
          authorize ::Tenancy::Directory.branches.new(company: Current.context.company), :create?, policy_class: ::Access::BranchPolicy
        end

        # time_zone is required: an omitted key is validated as nil (422) instead of silently taking the column default.
        def branch_params = { time_zone: nil }.merge(typed_params(name: String, time_zone: String, address: String, phone_e164: String))
      end
    end
  end
end
