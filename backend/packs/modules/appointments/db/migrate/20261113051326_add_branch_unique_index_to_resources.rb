# The target of the composite FK that proves the resource of an appointment belongs to the BRANCH of that appointment (and not
# only to its company). Additive and concurrent, so it takes no write lock.
class AddBranchUniqueIndexToResources < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :resources, %i[organization_id branch_id id], unique: true, name: "uq_resources_org_branch_id", algorithm: :concurrently
  end
end
