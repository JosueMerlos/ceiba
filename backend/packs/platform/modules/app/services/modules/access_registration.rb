module Modules
  # Declara en access los permisos de un manifiesto, con los roles que los reciben según su `role_grants` (la matriz de 04 es
  # DATO). Access.sync! los lleva después a la base con sus salvaguardas: este pack no escribe permisos ni concesiones.
  module AccessRegistration
    module_function

    def call(manifest)
      roles = Hash.new { |hash, key| hash[key] = [] }
      manifest.role_grants.each { |role, keys| keys.each { |key| roles[key] << role } }
      Access.register_permissions(
        manifest.key,
        manifest.permissions.to_h { |permission| [ permission.key, { description: permission.description, roles: roles[permission.key] } ] }
      )
    end
  end
end
