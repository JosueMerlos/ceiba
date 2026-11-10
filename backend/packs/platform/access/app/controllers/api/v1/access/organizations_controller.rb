module Api
  module V1
    module Access
      # The user's organizations and the detail of one. Organization is the tenant ROOT: it is listed and read without a
      # tenancy context (`show`'s context is opened by Access::Authorization from the route, after validating membership).
      class OrganizationsController < ::Api::BaseController
        route_context organization: :id

        def index
          # The Scope replaces the empty relation with the organizations of the user's memberships.
          none = ::Tenancy::Directory.organizations_for([])
          authorize none, :index?, policy_class: ::Access::OrganizationPolicy
          organizations = policy_scope(none, policy_scope_class: ::Access::OrganizationPolicy::Scope)
          # Summary (id, name, status): the context selector does not need the detail, which requires platform.organization.read.
          render_page(organizations, serializer: ::Tenancy::OrganizationSummarySerializer)
        end

        def show
          organization = Current.context.organization
          authorize organization, :show?, policy_class: ::Access::OrganizationPolicy
          render json: { data: ::Tenancy::OrganizationSerializer.new(organization).serializable_hash }
        end
      end
    end
  end
end
