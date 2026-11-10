module Access
  # after_provision hook: makes `extras[:owner]` the org_owner of the newly created organization. Runs in the SAME
  # transaction as the provisioning: on failure neither organization nor company remains. Tenancy knows neither Access nor
  # Identity; the pack hooks in from config.to_prepare.
  #
  # `owner` is an Identity::Principal::User (what Identity::ProvisionUser returns). Without `owner` the organization is
  # born ownerless; an `owner` of another type is a caller error and rolls everything back.
  module OwnerHook
    KEY = :access_owner

    module_function

    def call(result)
      owner = result.extras[:owner]
      return if owner.nil?
      raise ArgumentError, "extras[:owner] debe ser un Identity::Principal::User (recibió #{owner.class})" unless owner.is_a?(::Identity::Principal::User)

      GrantRole.call(user: owner, role_key: "org_owner", organization: result.organization)
    end

    # Idempotent by `key:`: safe to call on every reload.
    def register = Tenancy::ProvisionOrganization.after_provision(self, key: KEY)
  end
end
