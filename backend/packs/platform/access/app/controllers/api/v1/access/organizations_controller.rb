module Api
  module V1
    module Access
      # Las organizaciones del usuario y el detalle de una. Organization es la RAÍZ del tenant: se lista y se lee sin
      # contexto de tenancy (el contexto de `show` lo abre Access::Authorization desde la ruta, tras validar el membership).
      class OrganizationsController < ::Api::BaseController
        route_context organization: :id

        def index
          authorize ::Tenancy::Directory.organizations, :index?, policy_class: ::Access::OrganizationPolicy
          organizations = policy_scope(::Tenancy::Directory.organizations, policy_scope_class: ::Access::OrganizationPolicy::Scope)
          render_page(organizations, serializer: ::Tenancy::OrganizationSerializer)
        end

        def show
          organization = ::Tenancy::Directory.organization!(params[:id])
          authorize organization, :show?, policy_class: ::Access::OrganizationPolicy
          render json: { data: ::Tenancy::OrganizationSerializer.new(organization).serializable_hash }
        end
      end
    end
  end
end
