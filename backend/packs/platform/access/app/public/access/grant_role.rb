module Access
  # Concede un rol de SISTEMA a un usuario en un alcance de una organización. Es el camino público de escritura de
  # memberships (seeds, el hook del dueño, y las invitaciones de M4.01). Idempotente: repetir la misma concesión no duplica.
  #
  #   Access::GrantRole.call(user:, role_key: "org_admin", organization:)
  #   Access::GrantRole.call(user:, role_key: "company_manager", organization:, company:)
  #   Access::GrantRole.call(user:, role_key: "receptionist", organization:, branch:)   # la empresa se deduce de la sucursal
  #
  # `user`: cualquier objeto con `id` (Identity::Principal::User). `organization`, `company` y `branch` son los registros que
  # devuelven Tenancy::ProvisionOrganization / AddCompany / AddBranch (opacos aquí). El alcance debe ser el del rol; empresa y
  # sucursal deben ser de la organización dada. Lanza ArgumentError ante un rol desconocido o un alcance incoherente.
  module GrantRole
    module_function

    def call(user:, role_key:, organization:, company: nil, branch: nil)
      scope_level = SYSTEM_ROLES[role_key.to_s] or raise ArgumentError, "rol de sistema desconocido: #{role_key.inspect}"
      company_id, branch_id = scope_ids(role_key, scope_level, organization, company, branch)

      Tenancy.with_context(organization:) do
        Membership.find_or_create_by!(user_id: user.id, role: Role.find_by!(key: role_key.to_s), company_id:, branch_id:)
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      nil # dos concesiones simultáneas: gana el índice único y el resultado es el mismo
    end

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
