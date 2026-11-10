module Access
  # Role: a set of permissions with a scope (organization, company or branch). System roles are templates seeded by
  # Access.sync!, identical for every organization. GLOBAL table (no organization_id until custom roles exist).
  # PRIVATE model of the pack.
  class Role < ApplicationRecord
    SCOPE_LEVELS = %w[organization company branch].freeze

    enum :scope_level, SCOPE_LEVELS.index_by(&:itself), validate: true

    has_many :role_permissions, class_name: "Access::RolePermission", inverse_of: :role, dependent: :destroy
    # NO `has_many :memberships`, on purpose: Role is a global table and Membership is tenant. An association from a root
    # model to a tenant one would ignore the active tenant (see TenantIsolation.association_violations). The (restrict)
    # FK prevents deleting a role with memberships.

    validates :key, presence: true, uniqueness: true
  end
end
