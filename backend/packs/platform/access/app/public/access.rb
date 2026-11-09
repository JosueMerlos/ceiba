# API pública del pack platform/access (ADR-0007, ADR-0008, docs/architecture/04-access-control.md). El resto de la
# aplicación declara permisos con `Access.register_permissions`, autoriza con `Access::BasePolicy` y `Access::Authorization`
# y concede roles con `Access::GrantRole`; los modelos del pack son privados.
module Access
  # Roles de sistema (plantillas de plataforma) y su alcance. Es el catálogo cerrado de claves de rol que pueden aparecer
  # en una declaración de permisos; las POLICIES no las usan nunca (cop Ceiba/AccessPolicyRoles).
  SYSTEM_ROLES = {
    "org_owner" => "organization",
    "org_admin" => "organization",
    "company_manager" => "company",
    "branch_manager" => "branch",
    "receptionist" => "branch",
    "professional" => "branch"
  }.freeze

  class << self
    # Declara los permisos de un módulo y qué roles de sistema los reciben (la matriz de 04 codificada como DATOS). Se llama
    # desde `config.to_prepare` en un initializer del pack, así sobrevive a la recarga de código en desarrollo:
    #
    #   Rails.application.config.to_prepare do
    #     Access.register_permissions("appointments",
    #       "appointments.appointment.create" => { description: "Crear citas", roles: %w[company_manager branch_manager receptionist] })
    #   end
    #
    # Las claves siguen <modulo>.<recurso>.<accion> y empiezan por el módulo que las declara. Lanza ArgumentError ante una
    # declaración inválida (clave mal formada, prefijo ajeno, rol desconocido, clave repetida en otro módulo). Un permiso
    # que una policy usa y nadie registró hace fallar la suite (Access::BasePolicy#can? lo lanza y un spec escanea las
    # policies de todos los packs).
    def register_permissions(module_key, permissions)
      registry.register(module_key, permissions)
    end

    # Claves de todos los permisos registrados.
    def permission_keys = registry.keys

    def registered?(key) = registry.registered?(key)

    # Lleva el registro a la base: permisos, roles de sistema y role_permissions. Idempotente; corre en cada despliegue
    # (db:migrate lo encadena y db:seed lo ejecuta), nunca en el arranque de los procesos.
    def sync!(registry = self.registry) = CatalogSync.call(registry)

    def registry = @registry ||= PermissionRegistry.new
  end
end
