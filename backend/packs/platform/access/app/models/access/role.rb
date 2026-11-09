module Access
  # Rol: un conjunto de permisos con un alcance (organización, empresa o sucursal). Los de sistema son plantillas sembradas
  # por Access.sync!, iguales para todas las organizaciones. Tabla GLOBAL (ver la migración: sin organization_id hasta que
  # existan roles personalizados). Modelo PRIVADO del pack.
  class Role < ApplicationRecord
    SCOPE_LEVELS = %w[organization company branch].freeze

    enum :scope_level, SCOPE_LEVELS.index_by(&:itself), validate: true

    has_many :role_permissions, class_name: "Access::RolePermission", inverse_of: :role, dependent: :destroy
    # SIN `has_many :memberships`, a propósito: Role es una tabla global y Membership es tenant. Una asociación de un
    # modelo raíz hacia uno tenant ignoraría el tenant activo (ver TenantIsolation.association_violations). La FK
    # (restrict) impide borrar un rol con memberships.

    validates :key, presence: true, uniqueness: true
  end
end
