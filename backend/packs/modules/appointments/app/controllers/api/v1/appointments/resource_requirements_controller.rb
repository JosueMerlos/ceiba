module Api
  module V1
    module Appointments
      # The kinds of resource a service needs: one PUT replaces the whole set. The service is searched inside the route's
      # company (a foreign one is a 404) and needs the same permission as editing the service.
      class ResourceRequirementsController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def update
          service = ::Appointments::Service.where(company_id: Current.context.company.id).find(params[:service_id])
          authorize service, :update?, policy_class: ::Appointments::ServicePolicy
          ::Appointments::Staff::SetResourceRequirements.call(service:, kinds:)
          render json: { data: { service_id: service.id, kinds: ::Appointments::ServiceResourceRequirement.where(service_id: service.id).order(:kind).pluck(:kind) } }
        end

        private

        # Required, and every element a string: typed_params only checks the container.
        def kinds
          kinds = typed_params(kinds: Array)[:kinds]
          raise ActionController::BadRequest, "kinds debe ser una lista de textos" unless kinds&.all?(String)

          kinds
        end
      end
    end
  end
end
