# customers: the people a company serves. Tenant table, scoped to the COMPANY (the same phone in two companies of one
# group is two customers). phone_e164, email and notes hold ciphertext, so no CHECK can validate their format: the model
# does. phone_e164 and email are DETERMINISTIC ciphertext, which is what makes the unique index and the lookups work.
# full_name stays in the clear to allow prefix search.
class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :customers do |t|
      # No (organization_id, company_id) index: the prefix index below already covers it.
      t.tenant_reference :company, index: false
      t.string :full_name, null: false
      t.string :phone_e164, null: false
      t.string :email
      t.text :notes
      t.datetime :archived_at
      t.timestamps

      t.check_constraint "length(btrim(full_name)) > 0", name: "chk_customers_full_name_present"

      t.index %i[company_id phone_e164], unique: true, name: "uq_customers_company_phone"
      t.index "organization_id, company_id, lower(full_name) text_pattern_ops", name: "idx_customers_company_name_prefix"
      # The listing: active customers of a company, paginated by id.
      t.index %i[organization_id company_id id], where: "archived_at IS NULL", name: "idx_customers_company_active_id"
    end
  end
end
