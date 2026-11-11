module Api
  module V1
    module Appointments
      # The resources of the route's BRANCH. Everything is searched inside that branch (a resource of another branch, or
      # company, is a 404, never a 403) and the permission is asked at the branch. Inside this namespace `Appointments` is
      # Api::V1::Appointments: the pack's own constants are always written `::Appointments`.
      class ResourcesController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        # Active and paused resources, not archived ones, in creation order (the pagination cursor is the id).
        def index
          authorize branch_resources, :index?, policy_class: ::Appointments::ResourcePolicy
          resources = policy_scope(branch_resources.unarchived, policy_scope_class: ::Appointments::ResourcePolicy::Scope)
          render_page(resources, serializer: ::Appointments::ResourceSerializer)
        end

        def show
          resource = find_resource
          authorize resource, :show?, policy_class: ::Appointments::ResourcePolicy
          render_resource(resource)
        end

        def create
          resource = ::Appointments::Staff::CreateResource.call(company_id: Current.context.company.id, branch_id:, attributes: resource_params)
          render_resource(resource, status: :created)
        end

        def update
          resource = find_resource
          authorize resource, :update?, policy_class: ::Appointments::ResourcePolicy
          render_resource(::Appointments::Staff::UpdateResource.call(resource:, attributes: resource_params))
        end

        def destroy
          resource = find_resource
          authorize resource, :destroy?, policy_class: ::Appointments::ResourcePolicy
          ::Appointments::Staff::ArchiveResource.call(resource:)
          head :no_content
        end

        private

        def authorize_creation
          authorize ::Appointments::Resource.new(company_id: Current.context.company.id, branch_id:), :create?, policy_class: ::Appointments::ResourcePolicy
        end

        def branch_id = Current.context.branch.id

        def branch_resources = ::Appointments::Resource.where(company_id: Current.context.company.id, branch_id:)

        def find_resource = branch_resources.find(params[:resource_id])

        def render_resource(resource, status: :ok)
          render json: { data: ::Appointments::ResourceSerializer.new(resource).serializable_hash }, status:
        end

        def resource_params = typed_params(name: String, kind: String, active: :boolean)
      end
    end
  end
end
