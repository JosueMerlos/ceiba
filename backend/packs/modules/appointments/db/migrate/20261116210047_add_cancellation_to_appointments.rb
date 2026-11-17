# Who cancelled an appointment and why, as codes from a closed list (no free text, so no personal data). Both stay NULL until the
# appointment is cancelled and are mandatory once it is. The CHECKs are added NOT VALID and validated in their own migration.
class AddCancellationToAppointments < ActiveRecord::Migration[8.1]
  def change
    add_column :appointments, :cancelled_by, :string
    add_column :appointments, :cancellation_reason, :string
    add_check_constraint :appointments, "cancelled_by IS NULL OR cancelled_by = 'staff' OR cancelled_by = 'customer' OR cancelled_by = 'system'",
      name: "chk_appointments_cancelled_by", validate: false
    add_check_constraint :appointments,
      "cancellation_reason IS NULL OR cancellation_reason = 'customer_request' OR cancellation_reason = 'professional_unavailable' " \
      "OR cancellation_reason = 'business_decision' OR cancellation_reason = 'other'",
      name: "chk_appointments_cancellation_reason", validate: false
    add_check_constraint :appointments,
      "(status <> 'cancelled' AND cancelled_by IS NULL AND cancellation_reason IS NULL) " \
      "OR (status = 'cancelled' AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL)",
      name: "chk_appointments_cancellation", validate: false
  end
end
