module Api
  module V1
    module Appointments
      # A branch's override of a company service. Both the branch and the service are searched inside the route's company
      # (a foreign one is a 404). Authorization is by EFFECTIVE change against the current row and runs inside the write,
      # after the row is locked, so the permission is checked against what is really there.
      class ServiceOverridesController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def upsert
          service = company_services.find(params[:service_id])
          override = ::Appointments::Catalog::UpsertOverride.call(service:, branch_id:, attributes: override_params) do |candidate|
            authorize candidate, :upsert?, policy_class: ::Appointments::ServiceOverridePolicy
          end
          render json: { data: ::Appointments::ServiceOverrideSerializer.new(override).serializable_hash }
        end

        def destroy
          service = company_services.find(params[:service_id])
          override = ::Appointments::BranchServiceOverride.find_by!(branch_id:, service_id: service.id)
          ::Appointments::Catalog::RemoveOverride.call(override:) do |current|
            authorize current, :destroy?, policy_class: ::Appointments::ServiceOverridePolicy
          end
          head :no_content
        end

        private

        def branch_id = Current.context.branch.id

        def company_services = ::Appointments::Service.where(company_id: Current.context.company.id)

        # Only the keys SENT are returned (the merge leaves the rest alone); a value is a whole number or null (clears it).
        def override_params = typed_params(duration_minutes: Integer, price_minor: Integer)
      end
    end
  end
end
