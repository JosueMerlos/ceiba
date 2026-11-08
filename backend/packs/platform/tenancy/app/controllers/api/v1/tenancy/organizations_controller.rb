module Api
  module V1
    module Tenancy
      # Endpoint de ejemplo del contrato API (M0.06). Organization es la RAÍZ del tenant, no un registro tenant: se
      # consulta sin contexto de tenancy.
      #
      # TEMPORAL: todavía no hay autenticación (M0.07) ni autorización (M0.08), así que cualquiera podría leer
      # cualquier organización. Por eso solo existe con `config.x.api.open_organization_endpoint` (desarrollo y test);
      # en producción responde 404. M0.07/M0.08 lo protegen (la organización saldrá de los memberships del principal)
      # y eliminan el flag.
      class OrganizationsController < ::Api::BaseController
        before_action :ensure_temporarily_open

        def show
          organization = ::Tenancy::Organization.find(params[:id])
          render json: { data: ::Tenancy::OrganizationSerializer.new(organization).serializable_hash }
        end

        private

        def ensure_temporarily_open
          return if Rails.configuration.x.api.open_organization_endpoint

          raise ActionController::RoutingError, "No route matches [#{request.method}] #{request.path.inspect}"
        end
      end
    end
  end
end
