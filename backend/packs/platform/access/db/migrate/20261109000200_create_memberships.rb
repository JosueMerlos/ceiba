# memberships: who (user_id, global) has which role (role_id) at which scope of WHICH organization. Tenant table
# (create_tenant_table adds organization_id, UNIQUE (organization_id, id) and the RLS policy).
#
# Scope uses EXPLICIT columns and real FKs, no polymorphic scope_id:
#   organization  company_id NULL      branch_id NULL
#   company       company_id NOT NULL  branch_id NULL
#   branch        company_id NOT NULL  branch_id NOT NULL
# Enforced by the CHECK chk_memberships_scope. scope_level is denormalized from the role and the composite FK
# (role_id, scope_level) -> roles guarantees it never contradicts the role. The composite FK (organization_id, company_id,
# branch_id) -> branches guarantees the branch belongs to THAT company and THAT organization.
#
# on_delete: restrict everywhere (default): deleting a user, role or company with memberships must be explicit.
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

      # A user's role at a given scope may appear only once. NULLS NOT DISTINCT: NULLs of a higher scope count as equal
      # (otherwise the UNIQUE would not prevent duplicating an organization membership).
      t.index %i[organization_id user_id role_id company_id branch_id], unique: true, nulls_not_distinct: true,
        name: "uq_memberships_user_role_scope"
      # "Which organizations does this user belong to?" (context selector). The unique index's organization_id prefix
      # already covers "this user's memberships in this organization".
      t.index :user_id
      t.index %i[organization_id branch_id]
    end
  end
end
