module Access
  # Membership of a permission in a role. GLOBAL table with composite key (role_id, permission_key).
  class RolePermission < ApplicationRecord
    self.primary_key = %i[role_id permission_key]

    belongs_to :role, class_name: "Access::Role", inverse_of: :role_permissions
    belongs_to :permission, class_name: "Access::Permission", foreign_key: :permission_key, inverse_of: :role_permissions
  end
end
