module Access
  # Policy for Tenancy::Organization. It lives in access, not tenancy, because access depends on tenancy and not the
  # reverse (Packwerk rejects cycles); controllers pass it with `policy_class:`.
  class OrganizationPolicy < BasePolicy
    # "My organizations" (context selector): any authenticated user; the Scope narrows it to their own.
    def index? = principal.kind == :user

    def show? = can?("platform.organization.read", scope_of(record))
    def update? = can?("platform.organization.update", scope_of(record))
    def destroy? = can?("platform.organization.delete", scope_of(record))
    # create? inherits false: an organization is born ONLY through Tenancy::ProvisionOrganization.

    private

    def scope_of(organization) = Access::Scope.organization(organization.id)

    class Scope < BasePolicy::Scope
      def resolve
        return scope.none unless principal.kind == :user

        scope.or(Tenancy::Directory.organizations_for(principal.organization_ids))
      end
    end
  end
end
