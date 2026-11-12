# Replaced by the ends_at index (see the professional one).
class RemoveStartsIndexFromTimeOffsResource < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_index :time_offs, %i[resource_id starts_at], where: "resource_id IS NOT NULL",
      name: "idx_time_offs_resource_starts", algorithm: :concurrently
  end
end
