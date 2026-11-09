module Access
  # Lleva el registro de permisos a la base (Access.sync!). El registro es la FUENTE DE VERDAD: lo que ya no está declarado
  # se retira (permisos y concesiones); los roles de sistema se crean si faltan. Una transacción, idempotente.
  #
  # Sin escrituras masivas (insert_all/upsert_all): el catálogo es pequeño y el cop Ceiba/TenantBypass las prohíbe.
  class CatalogSync
    LOCK_NAME = "ceiba.access.sync".freeze

    def self.call(registry, allow_prune: false) = new(registry, allow_prune:).call

    def initialize(registry, allow_prune:)
      @definitions = registry.definitions
      @allow_prune = allow_prune
    end

    def call
      raise SyncRefused, "El registro de permisos está vacío (¿se cargaron los packs?): no se sincroniza para no borrar el catálogo." if @definitions.empty?

      ApplicationRecord.transaction(requires_new: true) do
        # Serializa despliegues simultáneos; se libera solo al terminar la transacción.
        ApplicationRecord.connection.select_value("SELECT pg_advisory_xact_lock(hashtext(#{ApplicationRecord.connection.quote(LOCK_NAME)}))")
        refuse_unauthorized_prune!
        sync_permissions
        roles = sync_roles
        sync_grants(roles)
      end
    end

    private

    # Lo que esta sincronización RETIRARÍA: permisos que ya nadie declara y concesiones que un rol ya no recibe.
    def refuse_unauthorized_prune!
      return if @allow_prune

      wanted_keys = @definitions.map(&:key)
      stale_permissions = Permission.where.not(key: wanted_keys).pluck(:key)
      stale_grants = RolePermission.joins(:role).where(roles: { key: SYSTEM_ROLES.keys }).pluck("roles.key", :permission_key)
        .reject { |role_key, key| @definitions.any? { |definition| definition.key == key && definition.roles.include?(role_key) } }
        .reject { |_role_key, key| stale_permissions.include?(key) }
      return if stale_permissions.empty? && stale_grants.empty?

      raise SyncRefused, "Access.sync! retiraría permisos #{stale_permissions.inspect} y concesiones #{stale_grants.inspect}. " \
                         "Si es intencional, repite con ACCESS_SYNC_ALLOW_PRUNE=1 (nada se ha modificado)."
    end

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
