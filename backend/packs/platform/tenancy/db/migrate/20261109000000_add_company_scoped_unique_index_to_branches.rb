# A branch is also identifiable by (organization_id, company_id, id): other tables (memberships) can reference a branch WITH
# its company through a composite FK, and the database rejects a branch membership whose company_id is not that branch's.
# The index is unique because `id` already is.
class AddCompanyScopedUniqueIndexToBranches < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :branches, %i[organization_id company_id id], unique: true, algorithm: :concurrently,
      name: "uq_branches_organization_id_company_id_id"
  end
end
