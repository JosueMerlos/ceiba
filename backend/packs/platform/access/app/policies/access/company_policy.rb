module Access
  # Policy for Tenancy::Company. See OrganizationPolicy for why it lives here.
  class CompanyPolicy < BasePolicy
    # Anyone with a membership in the active organization may list; the Scope filters which companies.
    def index? = principal.member?

    def show? = can?("platform.company.read", company_scope)
    def create? = can?("platform.company.create", Access::Scope.organization(record.organization_id))
    def update? = can?("platform.company.update", company_scope)

    private

    def company_scope = Access::Scope.company(organization_id: record.organization_id, company_id: record.id)

    class Scope < BasePolicy::Scope
      def resolve
        reach = reach("platform.company.read")
        return scope if reach.organization?

        scope.where(id: reach.company_ids)
      end
    end
  end
end
