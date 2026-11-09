module Tenancy
  # Lectura PÚBLICA de organizaciones, empresas y sucursales para otros packs. Los modelos de tenancy son privados
  # (docs/architecture/02-modular-monolith.md): quien necesita resolver una ruta o listar (access) lo hace por aquí y recibe
  # registros opacos y relaciones que filtra desde fuera. NO escribe: las altas son ProvisionOrganization / AddCompany /
  # AddBranch.
  #
  # Organización: raíz del tenant, se lee sin contexto. Empresas y sucursales: dentro de `Tenancy.with_context`, que acota
  # toda consulta a la organización activa (sin contexto lanzan ActsAsTenant::Errors::NoTenantSet).
  module Directory
    module_function

    def organization!(id) = Organization.find(id)

    # Relación sobre TODAS las organizaciones: el llamador la acota (p. ej. a las de los memberships del usuario).
    def organizations = Organization.all

    def companies = Company.all
    def company!(id) = Company.find(id)

    def branches = Branch.all
    def branch!(id, company_id:) = Branch.where(company_id:).find(id)
  end
end
