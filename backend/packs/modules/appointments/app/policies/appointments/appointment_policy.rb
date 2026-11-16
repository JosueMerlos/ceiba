module Appointments
  # Appointments are asked at the branch the route names. Booking and the agenda need the branch permission; the record of the
  # other actions is the appointment, already searched among the branch's. The staff permission (`update`) covers every action and
  # the detail with notes; a professional acts with `update_own` only on THEIR OWN appointments (the professional record linked to
  # their user and still assigned to the branch) and only on the actions the transition table opens to them. A professional's
  # agenda (`read_own`) lists only their own appointments.
  class AppointmentPolicy < Access::BasePolicy
    def create? = can?("appointments.appointment.create", context_scope(:branch))

    def index? = can?("appointments.appointment.read", context_scope(:branch)) || can?("appointments.appointment.read_own", context_scope(:branch))

    def show? = edit?(own_allowed: true)
    def update? = edit?(own_allowed: true)

    Transitions.actions.each do |action|
      define_method(:"#{action}?") { edit?(own_allowed: Transitions.fetch(action).own?) }
    end

    private

    def edit?(own_allowed:)
      can?("appointments.appointment.update", context_scope(:branch)) ||
        (own_allowed && can?("appointments.appointment.update_own", context_scope(:branch)) && own_appointment?)
    end

    def own_appointment? = Professional.of_user(principal.id, branch: Current.context.branch).exists?(id: record.professional_id)

    class Scope < Access::BasePolicy::Scope
      def resolve
        branch = context_scope(:branch)
        return scope if principal.can?("appointments.appointment.read", branch)
        return scope.none unless principal.can?("appointments.appointment.read_own", branch)

        scope.where(professional_id: Professional.of_user(principal.id, branch: Current.context.branch).select(:id))
      end
    end
  end
end
