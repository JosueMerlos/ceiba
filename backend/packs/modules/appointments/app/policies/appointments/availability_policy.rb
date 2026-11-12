module Appointments
  # Free slots are seen by whoever can book at the branch the route names; the record is that branch.
  class AvailabilityPolicy < Access::BasePolicy
    def show? = can?("appointments.appointment.create", context_scope(:branch))
  end
end
