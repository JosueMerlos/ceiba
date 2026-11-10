# Access control catalog. GLOBAL, not tenant: permissions are declared by the packs' manifests and system roles are
# platform templates, identical for every organization. Hence NO organization_id and NO RLS policy (the tenant-table
# guard checks this: Database::TenantTables.inconsistencies).
#
# `roles` has no organization_id yet: such a column would force registering the table as tenant, and a mixed table
# (global rows + per-organization rows) needs its own RLS policy. Decide that when custom roles exist.
class CreatePermissionsRolesAndRolePermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :permissions, id: false do |t|
      t.string :key, null: false, primary_key: true
      t.string :module_key, null: false
      t.string :description, null: false
      t.timestamps

      t.index :module_key
      # <module>.<resource>.<action>, and the key's module is its module_key.
      t.check_constraint "key ~ '^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$'", name: "chk_permissions_key_format"
      t.check_constraint "split_part(key, '.', 1) = module_key", name: "chk_permissions_module_prefix"
    end

    create_table :roles, id: :uuid do |t|
      t.string :key, null: false
      t.string :scope_level, null: false
      t.boolean :system, null: false, default: true
      t.timestamps

      t.index :key, unique: true, name: "uq_roles_key"
      # Target of memberships' composite FK (role_id, scope_level): the membership's scope IS the role's.
      t.index %i[id scope_level], unique: true, name: "uq_roles_id_scope_level"
      # OR instead of IN (...): on varchar, PostgreSQL dumps IN differently depending on whether the DB was created by
      # migrating or by loading the schema, which would cause false drift in structure.sql.
      t.check_constraint "scope_level = 'organization' OR scope_level = 'company' OR scope_level = 'branch'", name: "chk_roles_scope_level"
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
