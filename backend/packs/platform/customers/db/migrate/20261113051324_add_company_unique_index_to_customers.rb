# The target of the composite FK that proves a customer belongs to the company of the row that points at it
# (appointments). Additive and concurrent, so it takes no write lock.
class AddCompanyUniqueIndexToCustomers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :customers, %i[organization_id company_id id], unique: true, name: "uq_customers_org_company_id", algorithm: :concurrently
  end
end
