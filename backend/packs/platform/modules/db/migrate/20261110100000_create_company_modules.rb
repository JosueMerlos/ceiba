# company_modules: qué módulos tiene ENCENDIDOS cada empresa (ADR-0010, docs/architecture/05-module-system.md). Tabla tenant.
#
# - `module_key` es un identificador estable (nunca un booleano por módulo en companies). Una fila por (empresa, módulo): activar
#   crea la fila, desactivar pone `disabled_at` (los datos y settings se CONSERVAN) y reactivar la limpia.
# - `enabled_at` es el de la última activación.
# - `settings` son los overrides de la EMPRESA sobre los defaults del esquema del módulo (solo las claves que cambió).
#
# El UNIQUE (organization_id, company_id, module_key) hace de UNIQUE (company_id, module_key) (la empresa es de una sola organización)
# y es el destino de la FK compuesta de branch_module_settings. El índice parcial sirve a "las empresas con el módulo activo"
# (escáneres, docs/architecture/06).
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
