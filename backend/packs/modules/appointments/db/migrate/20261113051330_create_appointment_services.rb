# appointment_services: the services of an appointment as they were when it was booked (duration, buffers and price are copied,
# so a later catalog change does not rewrite history). Immutable: no updated_at and a trigger that rejects UPDATE (DELETE stays
# allowed for the cascade from its appointment and for purges). Tenant table.
class CreateAppointmentServices < ActiveRecord::Migration[8.1]
  def up
    create_tenant_table :appointment_services do |t|
      # No (organization_id, company_id) index of its own: the two below start with that pair.
      t.tenant_reference :company, index: false
      t.uuid :appointment_id, null: false
      t.uuid :service_id, null: false
      t.integer :position, null: false
      t.integer :duration_minutes, null: false
      t.integer :buffer_before_minutes, null: false
      t.integer :buffer_after_minutes, null: false
      t.bigint :price_minor, null: false
      t.string :currency, limit: 3, null: false
      t.datetime :created_at, null: false

      t.foreign_key :appointments, column: %i[organization_id company_id appointment_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointment_services_appointment", on_delete: :cascade
      t.foreign_key :services, column: %i[organization_id company_id service_id], primary_key: %i[organization_id company_id id],
        name: "fk_appointment_services_service"

      t.check_constraint "duration_minutes > 0", name: "chk_appointment_services_duration"
      t.check_constraint "buffer_before_minutes >= 0 AND buffer_after_minutes >= 0", name: "chk_appointment_services_buffers"
      t.check_constraint "price_minor >= 0", name: "chk_appointment_services_price"
      t.check_constraint "position >= 0", name: "chk_appointment_services_position"
      t.check_constraint "currency ~ '^[A-Z]{3}$'", name: "chk_appointment_services_currency"

      # One line per position of an appointment; it also serves the appointment side of the composite FK.
      t.index %i[organization_id company_id appointment_id position], unique: true, name: "uq_appointment_services_position"
      # The service side of the composite FK (deleting a service looks here).
      t.index %i[organization_id company_id service_id], name: "idx_appointment_services_service"
    end
    reject_updates :appointment_services
  end

  # The trigger goes with the table; the shared function stays because other tables may use it.
  def down
    drop_table :appointment_services
  end
end
