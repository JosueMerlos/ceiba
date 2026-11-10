# company_modules: which modules each company has ENABLED. Tenant table.
#
# - `module_key` is a stable identifier (never a boolean per module on companies). One row per (company, module): enabling
#   creates it, disabling sets `disabled_at` (data and settings are KEPT) and re-enabling clears it.
# - `enabled_at` is the last activation's.
# - `settings` are the COMPANY's overrides over the module schema's defaults (only the keys it changed).
#
# UNIQUE (organization_id, company_id, module_key) stands in for UNIQUE (company_id, module_key) (a company belongs to a single
# organization) and is the target of branch_module_settings' composite FK. The partial index serves "companies with the module
# active" (scanners).
class CreateCompanyModules < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :company_modules do |t|
      t.tenant_reference :company
      t.string :module_key, null: false
      t.datetime :enabled_at, null: false
      t.datetime :disabled_at
      t.jsonb :settings, null: false, default: {}
      t.timestamps

      t.unique_constraint %i[organization_id company_id module_key], name: "uq_company_modules_company_module"
      t.index %i[module_key company_id], where: "disabled_at IS NULL", name: "idx_company_modules_active"
      t.check_constraint "module_key ~ '^[a-z][a-z0-9_]*$'", name: "chk_company_modules_module_key"
      t.check_constraint "jsonb_typeof(settings) = 'object'", name: "chk_company_modules_settings_object"
    end
  end
end
