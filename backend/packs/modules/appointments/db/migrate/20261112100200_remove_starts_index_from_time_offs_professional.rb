# Replaced by the ends_at index: ordered by starts_at it cannot skip the past, and it lacks the tenant prefix.
class RemoveStartsIndexFromTimeOffsProfessional < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    remove_index :time_offs, %i[professional_id starts_at], where: "professional_id IS NOT NULL",
      name: "idx_time_offs_professional_starts", algorithm: :concurrently
  end
end
