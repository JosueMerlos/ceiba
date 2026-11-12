# What the engine reads: the blocking slots of a resource that end after the range starts. Same shape as the professional one.
class AddResourceBlocksIndexToAppointments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :appointments, %i[organization_id resource_id blocks_to],
      where: "resource_id IS NOT NULL AND status <> 'cancelled' AND status <> 'rescheduled'",
      name: "idx_appointments_resource_blocks", algorithm: :concurrently
  end
end
