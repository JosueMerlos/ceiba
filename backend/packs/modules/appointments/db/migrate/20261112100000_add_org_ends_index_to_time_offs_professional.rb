# The engine asks for the absences that END after the range starts, so the index is ordered by ends_at: the years of past
# absences are skipped instead of walked. The owner id is globally unique, so organization_id + owner already narrows to one
# person; company_id stays a cheap filter (a fourth column is not worth it).
class AddOrgEndsIndexToTimeOffsProfessional < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :time_offs, %i[organization_id professional_id ends_at], where: "professional_id IS NOT NULL",
      name: "idx_time_offs_professional_ends", algorithm: :concurrently
  end
end
