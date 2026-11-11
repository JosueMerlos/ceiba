module Appointments
  # Absences are asked at the scope of the branch the route names. The record is the absence (or a probe TimeOff describing
  # the owner, to list and create): staff with the manage permission act on the owners of that branch, and a person also
  # manages THEIR OWN absences with the own permission, when the owner is a record linked to their user and assigned to that
  # branch. Never on someone else's.
  class TimeOffPolicy < Access::BasePolicy
    def index? = can?("appointments.time_off.read", context_scope(:branch)) || own_time_off?
    def create? = can?("appointments.time_off.manage", context_scope(:branch)) || own_time_off?
    def destroy? = create?

    private

    def own_time_off?
      can?("appointments.time_off.manage_own", context_scope(:branch)) && record.own_for?(user_id: principal.id, branch_id: Current.context.branch.id)
    end
  end
end
