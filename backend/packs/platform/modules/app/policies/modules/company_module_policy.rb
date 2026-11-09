module Modules
  # Quién activa/desactiva módulos y escribe sus settings: `platform.company_module.manage` (org_owner y org_admin, matriz de 04).
  # `update?` recibe la empresa del contexto; `update_branch_settings?`, la sucursal de la ruta (un membership de sucursal no cubre
  # la empresa, pero el de organización o empresa sí cubre la sucursal).
  class CompanyModulePolicy < Access::BasePolicy
    PERMISSION = "platform.company_module.manage".freeze

    def update? = can?(PERMISSION, Access::Scope.company(organization_id: record.organization_id, company_id: record.id))

    def update_branch_settings?
      can?(PERMISSION, Access::Scope.branch(organization_id: record.organization_id, company_id: record.company_id, branch_id: record.id))
    end
  end
end
