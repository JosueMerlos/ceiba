# branch_module_settings: ONE branch's settings overrides for a module (only keys the schema allows at branch level).
# Tenant table.
#
# Two composite FKs keep integrity in the database: the branch must belong to THAT company and the module must have been enabled
# in the company at some point (company_modules keeps the row on disable, so overrides survive disabling and re-enabling).
class CreateBranchModuleSettings < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :branch_module_settings do |t|
      t.tenant_reference :company
      t.uuid :branch_id, null: false
      t.string :module_key, null: false
      t.jsonb :settings, null: false, default: {}
      t.timestamps

      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_branch_module_settings_branch"
      t.foreign_key :company_modules, column: %i[organization_id company_id module_key], primary_key: %i[organization_id company_id module_key],
        name: "fk_branch_module_settings_company_module"
      t.unique_constraint %i[organization_id branch_id module_key], name: "uq_branch_module_settings_branch_module"
      t.check_constraint "jsonb_typeof(settings) = 'object'", name: "chk_branch_module_settings_settings_object"
    end
  end
end
