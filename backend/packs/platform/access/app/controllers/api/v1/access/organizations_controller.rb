module Api
  module V1
    module Access
      # Las organizaciones del usuario y el detalle de una. Organization es la RAÍZ del tenant: se lista y se lee sin
      # contexto de tenancy (el contexto de `show` lo abre Access::Authorization desde la ruta, tras validar el membership).
      class OrganizationsController < ::Api::BaseController
        route_context organization: :id

        def index
          # El Scope reemplaza la relación vacía por las organizaciones de los memberships del usuario.
          none = ::Tenancy::Directory.organizations_for([])
          authorize none, :index?, policy_class: ::Access::OrganizationPolicy
          organizations = policy_scope(none, policy_scope_class: ::Access::OrganizationPolicy::Scope)
          # Resumen (id, name, status): el selector de contexto no necesita el detalle, que exige platform.organization.read.
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
