module Tenancy
  # Lectura PÚBLICA de organizaciones, empresas y sucursales para otros packs. SOLO LECTURA: devuelve registros y relaciones `readonly` (guardar, actualizar o borrar lanza ActiveRecord::ReadOnlyRecord). Los modelos de tenancy son privados
  # (docs/architecture/02-modular-monolith.md): quien necesita resolver una ruta o listar (access) lo hace por aquí y recibe
  # registros opacos y relaciones que filtra desde fuera. NO escribe: las altas son ProvisionOrganization / AddCompany /
  # AddBranch.
  #
  # Organización: raíz del tenant, se lee sin contexto. Empresas y sucursales: dentro de `Tenancy.with_context`, que acota
  # toda consulta a la organización activa (sin contexto lanzan ActsAsTenant::Errors::NoTenantSet).
  module Directory
    module_function

    def organization!(id) = Organization.readonly.find(id)

    # Solo las organizaciones indicadas (los ids salen de los memberships del usuario): no hay forma de pedir "todas".
    def organizations_for(ids) = Organization.readonly.where(id: ids)

    def companies = Company.readonly
    def company!(id) = Company.readonly.find(id)

    def branches = Branch.readonly
    def branch!(id, company_id:) = Branch.readonly.where(company_id:).find(id)

    # Empresa real de una sucursal (para verificar un alcance de sucursal), o nil si no existe en el tenant activo.
    def branch_company_id(branch_id) = Branch.where(id: branch_id).pick(:company_id)
  end
end
