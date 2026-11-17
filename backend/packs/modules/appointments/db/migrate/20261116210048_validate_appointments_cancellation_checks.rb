class ValidateAppointmentsCancellationChecks < ActiveRecord::Migration[8.1]
  def change
    validate_check_constraint :appointments, name: "chk_appointments_cancelled_by"
    validate_check_constraint :appointments, name: "chk_appointments_cancellation_reason"
    validate_check_constraint :appointments, name: "chk_appointments_cancellation"
  end
end
