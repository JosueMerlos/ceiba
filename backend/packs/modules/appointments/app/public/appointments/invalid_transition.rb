module Appointments
  # The appointment is not in a status the action can start from (somebody changed it first, or it already ended), or the action
  # is too early (a no-show before the start). The client refreshes the appointment.
  class InvalidTransition < FieldErrors
    def initialize(code) = super([ { field: :status, code: } ])
  end
end
