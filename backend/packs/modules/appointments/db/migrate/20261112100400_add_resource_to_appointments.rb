# The resource an appointment occupies (a room, a chair), if its services need one. Nullable: most appointments use none.
# The composite FK proves the resource belongs to the SAME company; it is added NOT VALID and validated in its own migration.
class AddResourceToAppointments < ActiveRecord::Migration[8.1]
  def change
    add_column :appointments, :resource_id, :uuid
    add_foreign_key :appointments, :resources, column: %i[organization_id company_id resource_id], primary_key: %i[organization_id company_id id],
      name: "fk_appointments_resource", validate: false
  end
end
