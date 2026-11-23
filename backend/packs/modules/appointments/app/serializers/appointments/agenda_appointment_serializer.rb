module Appointments
  # Fields match components.schemas.AgendaAppointment EXACTLY: the appointment plus the customer's name, for the agenda listing only.
  # `params[:customer_names]` is { customer id => full name }, empty for whoever may not see names.
  class AgendaAppointmentSerializer < AppointmentSerializer
    attribute(:customer_name) { |appointment| params.fetch(:customer_names)[appointment.customer_id] }
  end
end
