# Dos endurecimientos tras la revisión de M0.09:
#
# 1. settings de company_modules y branch_module_settings con tope de tamaño (pg_column_size < 16 KB): los settings viajan en cada /me y
#    un jsonb sin tope (sonda P3: 50 000 recordatorios = 4,5 MB) se convierte en una bomba. El esquema del módulo ya exige cotas; esto
#    es la red de seguridad en la base. Se añade sin validar y se valida aparte (strong_migrations).
# 2. El índice parcial de módulos activos empieza por organization_id: la consulta del gate (Modules::AccessGate) siempre va acotada
#    por el tenant.
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
