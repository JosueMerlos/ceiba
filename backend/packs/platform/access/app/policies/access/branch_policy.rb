module Access
  # Policy for Tenancy::Branch. See OrganizationPolicy for why it lives here.
  class BranchPolicy < BasePolicy
    def index? = principal.member?

    def show? = can?("platform.branch.read", branch_scope)
    def create? = can?("platform.branch.create", Access::Scope.company(organization_id: record.organization_id, company_id: record.company_id))
    def update? = can?("platform.branch.update", branch_scope)

    private

    def branch_scope
      Access::Scope.branch(organization_id: record.organization_id, company_id: record.company_id, branch_id: record.id)
    end

    class Scope < BasePolicy::Scope
      def resolve
        reach = reach("platform.branch.read")
        return scope if reach.organization?

        scope.where(company_id: reach.company_ids).or(scope.where(id: reach.branch_ids))
      end
    end
  end
end
