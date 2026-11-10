module Tenancy
  # PUBLIC read access to organizations, companies and branches for other packs. Returns `readonly` records and relations:
  # saving, updating or deleting ONE record raises ActiveRecord::ReadOnlyRecord. LIMIT: a relation still allows
  # `update_all`/`delete_all`/`readonly(false)` (they bypass records) and Tenancy::Context needs real models, so value
  # objects are not returned; the Ceiba/DirectoryWrites cop flags such bulk writes outside tenancy. Tenancy's models are
  # private: whoever must resolve a route or list (access) does it here and gets opaque records and relations to filter
  # from outside. It does NOT write: creation is ProvisionOrganization / AddCompany / AddBranch.
  #
  # Organization: the tenant root, read without context. Companies and branches: inside `Tenancy.with_context`, which scopes
  # every query to the active organization (without context they raise ActsAsTenant::Errors::NoTenantSet).
  module Directory
    module_function

    def organization!(id) = Organization.readonly.find(id)

    # Only the given organizations (ids come from the user's memberships): there is no way to ask for "all".
    def organizations_for(ids) = Organization.readonly.where(id: ids)

    def companies = Company.readonly
    def company!(id) = Company.readonly.find(id)

    def branches = Branch.readonly
    def branch!(id, company_id:) = Branch.readonly.where(company_id:).find(id)

    # A branch's actual company (to verify a branch scope), or nil if it is not in the active tenant.
    def branch_company_id(branch_id) = Branch.where(id: branch_id).pick(:company_id)
  end
end
