# services: the company's service catalog (what a branch can offer). Tenant table scoped to the COMPANY. Money is an integer
# in minor units (price_minor) plus its currency, which must be the company's (the model checks it: the database cannot see
# the company's currency from here). A service is archived (archived_at), never deleted: bookings will reference it.
#
# UNIQUE (organization_id, company_id, id) is the target of the composite FK from branch_service_overrides, which is what
# makes the database refuse an override that mixes a service of one company with a branch of another.
class CreateServices < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :services do |t|
      # No (organization_id, company_id) index: the listing index below already covers it.
      t.tenant_reference :company, index: false
      t.string :name, null: false
      t.integer :duration_minutes, null: false
      t.integer :buffer_before_minutes, null: false, default: 0
      t.integer :buffer_after_minutes, null: false, default: 0
      t.bigint :price_minor, null: false
      t.string :currency, null: false
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.datetime :archived_at
      t.timestamps

      t.check_constraint "length(btrim(name)) > 0", name: "chk_services_name_present"
      t.check_constraint "duration_minutes > 0", name: "chk_services_duration_positive"
      t.check_constraint "buffer_before_minutes >= 0", name: "chk_services_buffer_before"
      t.check_constraint "buffer_after_minutes >= 0", name: "chk_services_buffer_after"
      t.check_constraint "price_minor >= 0", name: "chk_services_price_non_negative"
      t.check_constraint "currency = 'NIO' OR currency = 'USD'", name: "chk_services_currency"

      t.index %i[organization_id company_id id], unique: true, name: "uq_services_organization_id_company_id_id"
      # The listing: non-archived services of a company, paginated by id.
      t.index %i[organization_id company_id id], where: "archived_at IS NULL", name: "idx_services_company_unarchived_id"
    end
  end
end
