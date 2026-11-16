module Api
  module V1
    module Appointments
      # The status actions on one appointment of the route's branch (another branch's or company's is a 404). Who may do each action
      # is the policy's (from the transition table); what each one does is the domain's. Rescheduling books a new appointment, so
      # it requires an Idempotency-Key like booking; the other actions accept one. Inside this namespace `Appointments` is
      # Api::V1::Appointments: the pack's own constants are always written `::Appointments`.
      class AppointmentTransitionsController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule
        include BranchOwner
        include BranchAppointment
        include ::Appointments::RequestParams

        # Every action but cancel and reschedule, which take a body, is the bare transition.
        PLAIN_ACTIONS = ::Appointments::Transitions.actions - %i[cancel reschedule]

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so it would skip the check
        # for a principal whose access was revoked. A denied request never reaches the key either.
        before_action :authorize_action
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent(*(::Appointments::Transitions.actions - %i[reschedule]), required: false)
        idempotent :reschedule, required: true

        PLAIN_ACTIONS.each do |action|
          define_method(action) { render_appointment(::Appointments::Transition.call(appointment:, action:)) }
        end

        def cancel
          reason = typed_params(reason: String)[:reason]
          render_appointment(::Appointments::Cancel.call(appointment:, reason:, cancelled_by: "staff"))
        end

        def reschedule
          values = typed_params(starts_at: String, professional_id: String)
          raise ActionController::ParameterMissing, :starts_at if values[:starts_at].blank?

          professional_id = values[:professional_id].present? ? uuid(values[:professional_id], :professional_id) : appointment.professional_id
          moved = ::Appointments::Reschedule.call(
            appointment:, company: Current.context.company, branch: Current.context.branch, starts_at: instant(values[:starts_at], :starts_at),
            professional: ::Appointments::Availability::ProfessionalChoice.resolve(professional_id, within: assigned_professionals), source: "panel"
          )
          render_appointment(moved, status: :created)
        end

        private

        def authorize_action = authorize(appointment, :"#{action_name}?", policy_class: ::Appointments::AppointmentPolicy)
      end
    end
  end
end
