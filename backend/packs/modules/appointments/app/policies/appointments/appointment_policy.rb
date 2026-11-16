module Appointments
  # Booking is asked at the branch the route names; the record is that branch. Same permission as seeing the free slots.
  class AppointmentPolicy < Access::BasePolicy
    def create? = can?("appointments.appointment.create", context_scope(:branch))
  end
end
