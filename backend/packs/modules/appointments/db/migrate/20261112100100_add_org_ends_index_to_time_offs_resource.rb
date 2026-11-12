# Same shape as the professional one, for the absences of a resource.
class AddOrgEndsIndexToTimeOffsResource < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :time_offs, %i[organization_id resource_id ends_at], where: "resource_id IS NOT NULL",
      name: "idx_time_offs_resource_ends", algorithm: :concurrently
  end
end
