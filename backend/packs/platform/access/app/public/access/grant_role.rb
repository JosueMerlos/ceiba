module Access
  # Grants a SYSTEM role to a user at a scope of an organization. It is the public write path for memberships (seeds,
  # the owner hook, invitations). Idempotent: repeating the same grant does not duplicate it.
  #
  #   Access::GrantRole.call(user:, role_key: "org_admin", organization:)
  #   Access::GrantRole.call(user:, role_key: "company_manager", organization:, company:)
  #   Access::GrantRole.call(user:, role_key: "receptionist", organization:, branch:)   # the company is derived from the branch
  #
  # Each NEW grant is audited (`membership.granted`, via Audit.record) in the same transaction; a repeated one is not.
  #
  # `user`: any object with `id` (Identity::Principal::User). `organization`, `company` and `branch` are the records
  # returned by Tenancy::ProvisionOrganization / AddCompany / AddBranch (opaque here). The scope must match the role's;
  # company and branch must belong to the given organization. Raises ArgumentError on an unknown role or inconsistent scope.
  module GrantRole
    module_function

    def call(user:, role_key:, organization:, company: nil, branch: nil)
      scope_level = SYSTEM_ROLES[role_key.to_s] or raise ArgumentError, "rol de sistema desconocido: #{role_key.inspect}"
      company_id, branch_id = scope_ids(role_key, scope_level, organization, company, branch)

      Tenancy.with_context(organization:) do
        role = Role.find_by!(key: role_key.to_s)
        attributes = { user_id: user.id, role:, company_id:, branch_id: }
        # A repeated grant changes nothing, so it is not audited again.
        audit_granted(Membership.create!(attributes), role_key) unless Membership.exists?(attributes)
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      nil # two concurrent grants: the unique index wins and the outcome is the same
    end

    # Same context and transaction as the grant: no event, no membership. `role` (not `role_key`) because the audit
    # privacy filter masks any field whose name contains `_key`.
    def audit_granted(membership, role_key)
      Audit.record(
        action: "membership.granted", subject: membership,
        after: { user_id: membership.user_id, role: role_key.to_s, scope_level: membership.scope_level, company_id: membership.company_id, branch_id: membership.branch_id }
      )
    end
    private_class_method :audit_granted

    def scope_ids(role_key, scope_level, organization, company, branch)
      case scope_level
      when "organization" then ensure_scope!(role_key, company.nil? && branch.nil?)
      when "company" then ensure_scope!(role_key, !company.nil? && branch.nil?)
      when "branch" then ensure_scope!(role_key, !branch.nil?)
      end
      [ company&.id || branch&.company_id, branch&.id ].tap do
        ensure_organization!(organization, company)
        ensure_organization!(organization, branch)
        raise ArgumentError, "la sucursal no pertenece a la empresa indicada" if branch && company && branch.company_id != company.id
      end
    end
    private_class_method :scope_ids

    def ensure_scope!(role_key, valid)
      raise ArgumentError, "El alcance no corresponde al rol #{role_key} (organización, empresa o sucursal según el rol)" unless valid
    end
    private_class_method :ensure_scope!

    def ensure_organization!(organization, record)
      return if record.nil? || record.organization_id == organization.id

      raise ArgumentError, "#{record.class.model_name.human} no pertenece a la organización #{organization.id}"
    end
    private_class_method :ensure_organization!
  end
end
