module Api
  module V1
    module Appointments
      # The professionals of the route's company. Everything is searched inside that company, so a professional of another
      # company is a 404, never a 403. Inside this namespace `Appointments` is Api::V1::Appointments: the pack's own
      # constants are always written `::Appointments`.
      class ProfessionalsController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        # Active and paused professionals, not archived ones, in creation order (the pagination cursor is the id).
        def index
          authorize company_professionals, :index?, policy_class: ::Appointments::ProfessionalPolicy
          professionals = policy_scope(company_professionals.unarchived.includes(*PRELOADS), policy_scope_class: ::Appointments::ProfessionalPolicy::Scope)
          render_page(professionals, serializer: ::Appointments::ProfessionalSerializer)
        end

        def show
          professional = find_professional
          authorize professional, :show?, policy_class: ::Appointments::ProfessionalPolicy
          render_professional(professional)
        end

        # The profile as seen from the route's branch: where a professional reads their own.
        def show_in_branch
          professional = find_professional
          authorize professional, :show_in_branch?, policy_class: ::Appointments::ProfessionalPolicy
          render_professional(professional)
        end

        def create
          professional = ::Appointments::Staff::CreateProfessional.call(company_id:, attributes: professional_params)
          render_professional(professional, status: :created)
        end

        def update
          professional = find_professional
          authorize professional, :update?, policy_class: ::Appointments::ProfessionalPolicy
          render_professional(::Appointments::Staff::UpdateProfessional.call(professional:, attributes: professional_params))
        end

        def destroy
          professional = find_professional
          authorize professional, :destroy?, policy_class: ::Appointments::ProfessionalPolicy
          ::Appointments::Staff::ArchiveProfessional.call(professional:)
          head :no_content
        end

        private

        PRELOADS = %i[branch_assignments professional_services].freeze
        private_constant :PRELOADS

        def authorize_creation
          authorize ::Appointments::Professional.new(company_id:), :create?, policy_class: ::Appointments::ProfessionalPolicy
        end

        def company_id = Current.context.company.id

        def company_professionals = ::Appointments::Professional.where(company_id:)

        def find_professional = company_professionals.includes(*PRELOADS).find(params[:professional_id])

        def render_professional(professional, status: :ok)
          render json: { data: ::Appointments::ProfessionalSerializer.new(professional).serializable_hash }, status:
        end

        def professional_params = typed_params(display_name: String, user_id: String, active: :boolean)
      end
    end
  end
end
