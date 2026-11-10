# 1. Size cap on settings of company_modules and branch_module_settings (pg_column_size < 16 KB): settings travel in every /me
#    and an uncapped jsonb (50,000 reminders = 4.5 MB) becomes a bomb. The module schema already requires bounds; this is the
#    database safety net. Added unvalidated and validated separately (strong_migrations).
# 2. The partial index of active modules starts with organization_id: the gate query (Modules::AccessGate) is always
#    tenant-scoped.
class AddSettingsSizeChecksAndGateIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_check_constraint :company_modules, "pg_column_size(settings) < 16384", name: "chk_company_modules_settings_size", validate: false
    validate_check_constraint :company_modules, name: "chk_company_modules_settings_size"
    add_check_constraint :branch_module_settings, "pg_column_size(settings) < 16384", name: "chk_branch_module_settings_settings_size", validate: false
    validate_check_constraint :branch_module_settings, name: "chk_branch_module_settings_settings_size"

    remove_index :company_modules, name: "idx_company_modules_active", algorithm: :concurrently
    add_index :company_modules, %i[organization_id module_key company_id], where: "disabled_at IS NULL", name: "idx_company_modules_active", algorithm: :concurrently
  end

  def down
    remove_index :company_modules, name: "idx_company_modules_active", algorithm: :concurrently
    add_index :company_modules, %i[module_key company_id], where: "disabled_at IS NULL", name: "idx_company_modules_active", algorithm: :concurrently
    remove_check_constraint :branch_module_settings, name: "chk_branch_module_settings_settings_size"
    remove_check_constraint :company_modules, name: "chk_company_modules_settings_size"
  end
end
