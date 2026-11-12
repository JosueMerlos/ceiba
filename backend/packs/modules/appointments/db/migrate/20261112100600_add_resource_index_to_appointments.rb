# The side of the composite FK (deleting a resource looks here).
class AddResourceIndexToAppointments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :appointments, %i[organization_id company_id resource_id], where: "resource_id IS NOT NULL",
      name: "idx_appointments_resource", algorithm: :concurrently
  end
end
