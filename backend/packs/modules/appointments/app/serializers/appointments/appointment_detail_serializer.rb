module Appointments
  # Fields match components.schemas.AppointmentDetail EXACTLY: the appointment plus its notes, for whoever may edit it.
  class AppointmentDetailSerializer < AppointmentSerializer
    attributes :notes
  end
end
