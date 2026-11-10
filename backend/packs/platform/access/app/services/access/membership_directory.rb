module Access
  # The ONLY path that reads memberships across ALL organizations: "which organizations does this user belong to?"
  # (context selector; GET /organizations). It is an explicit privileged path, listed in AllowedFiles of the
  # Ceiba/TenantBypass cop (CODEOWNERS review). It only READS and only returns the user's own organization ids.
  #
  # Once RLS is enabled this read will need a per-user policy or a platform role with BYPASSRLS.
  module MembershipDirectory
    module_function

    def organization_ids_for(user_id)
      ActsAsTenant.without_tenant { Membership.where(user_id:).distinct.pluck(:organization_id) }
    end
  end
end
