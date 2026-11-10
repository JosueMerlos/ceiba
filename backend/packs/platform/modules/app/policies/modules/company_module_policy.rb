module Modules
  # Who enables/disables modules and writes settings: `platform.company_module.manage` (org_owner and org_admin).
  # `update?` takes the context's company; `update_branch_settings?` the route's branch (a branch membership does not cover
  # the company, but an organization or company membership covers the branch).
  class CompanyModulePolicy < Access::BasePolicy
    def update? = can?("platform.company_module.manage", Access::Scope.company(organization_id: record.organization_id, company_id: record.id))

    def update_branch_settings?
      can?("platform.company_module.manage", Access::Scope.branch(organization_id: record.organization_id, company_id: record.company_id, branch_id: record.id))
    end
  end
end
