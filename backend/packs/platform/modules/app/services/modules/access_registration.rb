module Modules
  # Declares a manifest's permissions in access, with the roles that receive them per its `role_grants` (the matrix is DATA).
  # Access.sync! later persists them with its safeguards: this pack writes no permissions or grants itself.
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
