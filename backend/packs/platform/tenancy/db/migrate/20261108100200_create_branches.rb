# branches: tenant table hanging from companies by a COMPOSITE FK (organization_id, company_id) -> companies
# (organization_id, id) (t.tenant_reference): the database prevents a branch of organization A from hanging off a company of
# B even if code skips validations.
#
# on_delete: restrict (the default) on both FKs, like companies: a company with branches is not deleted by accident.
class CreateBranches < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :branches do |t|
      t.tenant_reference :company
      t.string :name, null: false
      t.string :time_zone, null: false, default: "America/Managua"
      t.string :address
      t.string :phone_e164
      t.string :status, null: false, default: "active"
      t.timestamps

      t.check_constraint "status = 'active' OR status = 'inactive'", name: "chk_branches_status"
      t.check_constraint "phone_e164 IS NULL OR phone_e164 ~ '^\\+[1-9][0-9]{6,14}$'", name: "chk_branches_phone_e164"
    end
  end
end
