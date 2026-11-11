module Appointments
  # Weekly hours are asked at the scope of the branch the route names. The record is the owner (branch, professional or
  # resource): a person also reads THEIR OWN hours with the own-schedule permission, when the owner
  # is a record linked to their user and assigned to that branch. Editing is never "own".
  class SchedulePolicy < Access::BasePolicy
    def show? = can?("appointments.schedule.read", context_scope(:branch)) || own_schedule?
    def update? = can?("appointments.schedule.manage", context_scope(:branch))

    private

    def own_schedule?
      can?("appointments.schedule.read_own", context_scope(:branch)) && record.is_a?(Professional) && record.own_in_branch?(user_id: principal.id, branch_id: Current.context.branch.id)
    end
  end
end
