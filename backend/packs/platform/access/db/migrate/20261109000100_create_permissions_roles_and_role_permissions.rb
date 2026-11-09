# Catálogo de control de acceso (ADR-0008). GLOBAL, no tenant: los permisos los declaran los manifiestos de los packs y los
# roles de sistema son plantillas de plataforma, iguales para todas las organizaciones. Por eso NO llevan organization_id
# ni política RLS (el guardián de tablas tenant lo comprueba: Database::TenantTables.inconsistencies).
#
# `roles` NO lleva organization_id todavía (docs/architecture/04 lo preveía NULL para roles personalizados, P3): una
# columna organization_id obligaría a registrar la tabla como tenant, y una tabla mixta (filas globales + filas de una
# organización) necesita una política RLS propia. Cuando existan los roles personalizados se decide entonces (ver 04).
class CreatePermissionsRolesAndRolePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :permissions, id: false do |t|
      t.string :key, null: false, primary_key: true
      t.string :module_key, null: false
      t.string :description, null: false
      t.timestamps

      t.index :module_key
      # <modulo>.<recurso>.<accion>, y el módulo de la clave es su module_key.
      t.check_constraint "key ~ '^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$'", name: "chk_permissions_key_format"
      t.check_constraint "split_part(key, '.', 1) = module_key", name: "chk_permissions_module_prefix"
    end

    create_table :roles, id: :uuid do |t|
      t.string :key, null: false
      t.string :scope_level, null: false
      t.boolean :system, null: false, default: true
      t.timestamps

      t.index :key, unique: true, name: "uq_roles_key"
      # Para la FK compuesta (role_id, scope_level) de memberships: el alcance del membership ES el del rol.
      t.index %i[id scope_level], unique: true, name: "uq_roles_id_scope_level"
      t.check_constraint "scope_level IN ('organization', 'company', 'branch')", name: "chk_roles_scope_level"
    end

    create_table :role_permissions, primary_key: %i[role_id permission_key] do |t|
      t.uuid :role_id, null: false
      t.string :permission_key, null: false
      t.timestamps

      t.index :permission_key
      t.foreign_key :roles, column: :role_id, name: "fk_role_permissions_role", on_delete: :cascade
      t.foreign_key :permissions, column: :permission_key, primary_key: :key, name: "fk_role_permissions_permission", on_delete: :cascade
    end
  end
end
