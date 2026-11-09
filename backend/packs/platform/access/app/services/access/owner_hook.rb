module Access
  # Hook after_provision: convierte a `extras[:owner]` en el org_owner de la organización recién creada. Corre en la MISMA
  # transacción que la provisión: si falla, no queda ni organización ni empresa. Tenancy no conoce a Access ni a Identity; el
  # pack se engancha desde config.to_prepare (config/initializers/owner_hook.rb).
  #
  # `owner` es un Identity::Principal::User (lo que devuelve Identity::ProvisionUser). Sin `owner` la organización nace sin
  # dueño (el alta con invitación llega con M4.01); un `owner` de otro tipo es un error del llamador y revierte todo.
  module OwnerHook
    KEY = :access_owner

    module_function

    def call(result)
      owner = result.extras[:owner]
      return if owner.nil?
      raise ArgumentError, "extras[:owner] debe ser un Identity::Principal::User (recibió #{owner.class})" unless owner.is_a?(::Identity::Principal::User)

      GrantRole.call(user: owner, role_key: "org_owner", organization: result.organization)
    end

    # Idempotente por `key:`: se puede llamar en cada recarga.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
