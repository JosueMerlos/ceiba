class ValidateAppointmentsResourceFk < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :appointments, name: "fk_appointments_resource"
  end
end
