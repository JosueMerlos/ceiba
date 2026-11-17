module Access
  # Policy for a company's branding (the Tenancy::Company record). Reading it from the panel needs the same permission as
  # editing it: the public page already shows what anyone may read.
  class BrandingPolicy < BasePolicy
    def show? = can?("platform.branding.update", company_scope)
    def update? = can?("platform.branding.update", company_scope)

    private

    def company_scope = Access::Scope.company(organization_id: record.organization_id, company_id: record.id)
  end
end
