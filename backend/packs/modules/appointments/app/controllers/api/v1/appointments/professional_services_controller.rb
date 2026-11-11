module Api
  module V1
    module Appointments
      # The services a professional performs: one PUT replaces the whole set. The professional is searched inside the route's
      # company (a foreign one is a 404) and the company-level manage permission is required.
      class ProfessionalServicesController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def update
          professional = ::Appointments::Professional.where(company_id: Current.context.company.id).find(params[:professional_id])
          authorize professional, :update?, policy_class: ::Appointments::ProfessionalPolicy
          ::Appointments::Staff::SetServices.call(professional:, service_ids:)
          render json: { data: ::Appointments::ProfessionalSerializer.new(professional.reload).serializable_hash }
        end

        private

        # Required, and every element a string: typed_params only checks the container.
        def service_ids
          ids = typed_params(service_ids: Array)[:service_ids]
          raise ActionController::BadRequest, "service_ids debe ser una lista de textos" unless ids&.all?(String)

          ids
        end
      end
    end
  end
end
