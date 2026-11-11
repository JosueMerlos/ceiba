# branch_service_overrides: a branch's own duration and/or price for a company service. Tenant table; company_id is stored so
# the composite FKs can prove the branch and the service belong to the SAME company (and organization). A row with neither
# value would override nothing, so the CHECK forbids it. The currency is not stored: the override inherits the service's.
class CreateBranchServiceOverrides < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :branch_service_overrides do |t|
      t.tenant_reference :company, index: false
      t.uuid :branch_id, null: false
      t.uuid :service_id, null: false
      t.integer :duration_minutes
      t.bigint :price_minor
      t.timestamps

      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_bso_branch"
      t.foreign_key :services, column: %i[organization_id company_id service_id], primary_key: %i[organization_id company_id id],
        name: "fk_bso_service"

      t.check_constraint "duration_minutes > 0", name: "chk_bso_duration_positive"
      t.check_constraint "price_minor >= 0", name: "chk_bso_price_non_negative"
      t.check_constraint "duration_minutes IS NOT NULL OR price_minor IS NOT NULL", name: "chk_bso_overrides_something"

      t.index %i[branch_id service_id], unique: true, name: "uq_bso_branch_service"
      # The service side of the composite FK (cascade-free: restrict) and "which overrides does this service have".
      t.index %i[organization_id company_id service_id], name: "idx_bso_service"
    end
  end
end
