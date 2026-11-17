module Api
  module V1
    module Appointments
      # Absences of a professional of the route's company, seen from the COMPANY instead of a branch. The branch routes only
      # reach professionals assigned to their branch, so the absences of one with no branch can only be read and deleted here.
      # The professional is searched among the company's own (a foreign one is a 404) and the absence ONLY among that
      # professional's. Creating stays on the branch routes.
      class CompanyTimeOffsController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def index
          authorize professional, :index?, policy_class: ::Appointments::CompanyTimeOffPolicy
          time_offs = policy_scope(professional_time_offs, policy_scope_class: ::Appointments::CompanyTimeOffPolicy::Scope)
          render_page(time_offs, serializer: ::Appointments::TimeOffSerializer)
        end

        def destroy
          time_off = professional_time_offs.find(params[:professional_time_off_id])
          authorize professional, :destroy?, policy_class: ::Appointments::CompanyTimeOffPolicy
          ::Appointments::Staff::DeleteTimeOff.call(time_off:)
          head :no_content
        end

        private

        def company_id = Current.context.company.id

        def professional = @professional ||= ::Appointments::Professional.where(company_id:).find(params[:professional_id])

        def professional_time_offs = ::Appointments::TimeOff.where(company_id:).owned_by(professional)
      end
    end
  end
end
