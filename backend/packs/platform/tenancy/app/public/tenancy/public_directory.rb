module Tenancy
  # The ONLY anonymous, cross-organization reader: it finds a company by its public slug (unique across all organizations)
  # when there is no tenant yet, so a public page can open the right tenant context. It is a privileged path listed in
  # AllowedFiles of Ceiba/TenantBypass (CODEOWNERS review). It reads one company and its organization, both readonly, and
  # nothing else; every other read stays inside Tenancy.with_context.
  #
  # Once RLS is enforced this lookup needs a SECURITY DEFINER function or the privileged role.
  module PublicDirectory
    module_function

    # { organization:, company: } or nil. The slug is normalized as Company does; one that cannot be a slug (wrong format,
    # reserved, not a String) is nil without touching the database.
    def company_by_slug(slug)
      slug = Company.normalize_value_for(:slug, slug) if slug.is_a?(String)
      return unless possible_slug?(slug)

      company = ActsAsTenant.without_tenant { Company.readonly.find_by(slug:) }
      return unless company

      { organization: Organization.readonly.find(company.organization_id), company: }
    end

    def possible_slug?(slug) = slug.is_a?(String) && Company::SLUG_FORMAT.match?(slug) && Company::RESERVED_SLUGS.exclude?(slug)
    private_class_method :possible_slug?
  end
end
