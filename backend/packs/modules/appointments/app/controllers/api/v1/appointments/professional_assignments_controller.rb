module Api
  module V1
    module Appointments
      # A professional's assignment to the route's branch. The professional is searched inside the route's company (a foreign
      # one is a 404) and the permission is asked at the branch, so a branch role only reaches its own branch.
      class ProfessionalAssignmentsController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def upsert
          professional = find_professional
          authorize professional, :upsert?, policy_class: ::Appointments::ProfessionalAssignmentPolicy
          ::Appointments::Staff::AssignBranch.call(professional:, branch_id: Current.context.branch.id)
          render_professional(professional)
        end

        def destroy
          professional = find_professional
          authorize professional, :destroy?, policy_class: ::Appointments::ProfessionalAssignmentPolicy
          ::Appointments::Staff::UnassignBranch.call(professional:, branch_id: Current.context.branch.id)
          head :no_content
        end

        private

        def find_professional = ::Appointments::Professional.where(company_id: Current.context.company.id).find(params[:professional_id])

        def render_professional(professional)
          render json: { data: ::Appointments::ProfessionalSerializer.new(professional.reload).serializable_hash }
        end
      end
    end
  end
end
