module Access
  # Resolves a request's context from the ROUTE and validates it against the principal's memberships before the action runs:
  #
  #   organizations/:organization_id/companies/:company_id/branches/:branch_id
  #
  # Rules:
  #   - Organization, company and branch come from the ROUTE, never from the body.
  #   - Nonexistent organization or no membership => 404 (the SAME as nonexistent: existence is not revealed).
  #   - Company or branch outside its memberships' scope, or of another organization/company => 404.
  #   - Suspended organization (principal is a member) => 403 Access::OrganizationSuspended. An ACCESS decision, not a
  #     tenancy one: Tenancy.with_context does accept a suspended organization.
  #   - Everything runs inside Tenancy.with_context (one transaction, READ-ONLY on GET/HEAD); anything the action or a
  #     verify_* raises rolls back what was written.
  #
  # The request's only permissions query happens here (Principal::User#activate!).
  class RouteContextResolver
    def self.call(principal:, organization_id:, company_id: nil, branch_id: nil, read_only: false, &)
      new(principal:, organization_id:, company_id:, branch_id:, read_only:).call(&)
    end

    def initialize(principal:, organization_id:, company_id:, branch_id:, read_only:)
      @read_only = read_only
      @principal = principal
      @organization_id = organization_id
      @company_id = company_id
      @branch_id = branch_id
    end

    def call(&block)
      organization = Tenancy::Directory.organization!(identifier(@organization_id))
      Tenancy.with_context(organization:, principal: @principal, read_only: @read_only) do
        @principal.activate!(organization.id)
        not_found! unless @principal.member?
        raise OrganizationSuspended, "La organización está suspendida" if organization.suspended?

        within_company_and_branch(organization, &block)
      end
    end

    private

    def within_company_and_branch(organization, &block)
      # A branch without a company is not a valid route: reject it, do not ignore it.
      not_found! if @company_id.nil? && !@branch_id.nil?
      return block.call(Current.context) if @company_id.nil?

      company = Tenancy::Directory.company!(identifier(@company_id))
      not_found! unless @principal.sees_company?(company.id)
      branch = resolve_branch(company)
      Tenancy.with_context(organization:, company:, branch:, principal: @principal, &block)
    end

    def resolve_branch(company)
      return if @branch_id.nil?

      branch = Tenancy::Directory.branch!(identifier(@branch_id), company_id: company.id)
      not_found! unless @principal.sees_branch?(branch.id, company.id)
      branch
    end

    # A non-string param (?organization_id[]=…) is not an id: same 404.
    def identifier(value) = value.is_a?(String) ? value : not_found!

    def not_found! = raise(ActiveRecord::RecordNotFound, "No se encontró el recurso")
  end
end
