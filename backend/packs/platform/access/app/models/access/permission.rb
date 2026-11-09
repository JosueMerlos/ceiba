module Access
  # Permiso declarado por un módulo (<modulo>.<recurso>.<accion>). Tabla GLOBAL, sincronizada desde el registro en memoria
  # (Access.register_permissions) por Access.sync!. Modelo PRIVADO del pack.
  class Permission < ApplicationRecord
    self.primary_key = "key"

    KEY_FORMAT = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/

    has_many :role_permissions, class_name: "Access::RolePermission", foreign_key: :permission_key, inverse_of: :permission,
      dependent: :destroy

    validates :key, format: { with: KEY_FORMAT }
    validates :module_key, :description, presence: true
  end
end
