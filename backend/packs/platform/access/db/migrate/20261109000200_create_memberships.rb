# memberships: quién (user_id, global) tiene qué rol (role_id) en qué alcance de QUÉ organización. Tabla tenant
# (organization_id, UNIQUE (organization_id, id) y política RLS las pone create_tenant_table).
#
# Alcance con columnas EXPLÍCITAS y FKs reales (ADR-0008), nada de scope_id polimórfico:
#   organization  company_id NULL      branch_id NULL
#   company       company_id NOT NULL  branch_id NULL
#   branch        company_id NOT NULL  branch_id NOT NULL
# Lo impone el CHECK chk_memberships_scope (criterio 6). scope_level se denormaliza desde el rol y la FK compuesta
# (role_id, scope_level) -> roles garantiza que nunca contradiga al rol. La FK compuesta (organization_id, company_id,
# branch_id) -> branches garantiza que la sucursal es de ESA empresa y de ESA organización.
#
# on_delete: restrict en todo (default): borrar un usuario, un rol o una empresa con memberships es una decisión explícita.
class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_tenant_table :memberships do |t|
      t.uuid :user_id, null: false
      t.uuid :role_id, null: false
      t.string :scope_level, null: false
      t.tenant_reference :company, null: true
      t.uuid :branch_id
      t.timestamps

      t.foreign_key :users, column: :user_id, name: "fk_memberships_user"
      t.foreign_key :roles, column: %i[role_id scope_level], primary_key: %i[id scope_level], name: "fk_memberships_role_scope"
      t.foreign_key :branches, column: %i[organization_id company_id branch_id], primary_key: %i[organization_id company_id id],
        name: "fk_memberships_branch"

      t.check_constraint <<~SQL.squish, name: "chk_memberships_scope"
        (scope_level = 'organization' AND company_id IS NULL AND branch_id IS NULL)
        OR (scope_level = 'company' AND company_id IS NOT NULL AND branch_id IS NULL)
        OR (scope_level = 'branch' AND company_id IS NOT NULL AND branch_id IS NOT NULL)
      SQL

      # Un mismo rol del mismo usuario en el mismo alcance una sola vez. NULLS NOT DISTINCT: los NULL de un alcance
      # superior cuentan como iguales (si no, el UNIQUE no impediría duplicar un membership de organización).
      t.index %i[organization_id user_id role_id company_id branch_id], unique: true, nulls_not_distinct: true,
        name: "uq_memberships_user_role_scope"
      # "¿A qué organizaciones pertenece este usuario?" (selector de contexto, ADR-0028). El prefijo organization_id del
      # índice único ya cubre "los memberships de este usuario en esta organización".
      t.index :user_id
      t.index %i[organization_id branch_id]
    end
  end
end
