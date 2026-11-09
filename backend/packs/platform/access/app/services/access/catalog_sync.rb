module Access
  # Lleva el registro de permisos a la base (Access.sync!). El registro es la FUENTE DE VERDAD: lo que ya no está declarado
  # se retira (permisos y concesiones); los roles de sistema se crean si faltan. Una transacción, idempotente.
  #
  # Sin escrituras masivas (insert_all/upsert_all): el catálogo es pequeño y el cop Ceiba/TenantBypass las prohíbe.
  class CatalogSync
    def self.call(registry) = new(registry).call

    def initialize(registry)
      @definitions = registry.definitions
    end

    def call
      ApplicationRecord.transaction(requires_new: true) do
        sync_permissions
        roles = sync_roles
        sync_grants(roles)
      end
    end

    private

    def sync_permissions
      existing = Permission.all.index_by(&:key)
      @definitions.each do |definition|
        permission = existing[definition.key] || Permission.new(key: definition.key)
        permission.update!(module_key: definition.module_key, description: definition.description)
      end
      stale = existing.keys - @definitions.map(&:key)
      Permission.where(key: stale).destroy_all if stale.any?
    end

    def sync_roles
      existing = Role.all.index_by(&:key)
      SYSTEM_ROLES.to_h do |key, scope_level|
        role = existing[key] || Role.new(key:)
        role.update!(scope_level:, system: true)
        [ key, role ]
      end
    end

    def sync_grants(roles)
      current = RolePermission.where(role_id: roles.values.map(&:id)).pluck(:role_id, :permission_key).group_by(&:first)
      roles.each do |key, role|
        wanted = @definitions.select { |definition| definition.roles.include?(key) }.map(&:key)
        have = (current[role.id] || []).map(&:last)
        (wanted - have).each { |permission_key| RolePermission.create!(role:, permission_key:) }
        RolePermission.where(role_id: role.id, permission_key: have - wanted).delete_all if (have - wanted).any?
      end
    end
  end
end
