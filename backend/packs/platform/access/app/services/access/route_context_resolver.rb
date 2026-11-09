module Access
  # Resuelve el contexto de una request desde la RUTA y lo valida contra los memberships del principal, antes de que corra la
  # acción (docs/architecture/03-multi-tenancy.md, 04-access-control.md):
  #
  #   organizations/:organization_id/companies/:company_id/branches/:branch_id
  #
  # Reglas:
  #   - La organización, la empresa y la sucursal salen de la RUTA, nunca del cuerpo.
  #   - Organización inexistente o sin membership del principal => 404 (el MISMO que una inexistente: no revela existencia).
  #   - Empresa o sucursal fuera del alcance de sus memberships, o de otra organización/empresa => 404.
  #   - Organización suspendida (el principal es miembro) => 403 Access::OrganizationSuspended. Es una decisión de ACCESO, no de
  #     tenancy: Tenancy.with_context sí acepta una organización suspendida.
  #   - Todo corre dentro de Tenancy.with_context (una transacción); lo que lance la acción, o un verify_*, revierte lo escrito.
  #
  # La única consulta de permisos de la request ocurre aquí (Principal::User#activate!).
  class RouteContextResolver
    def self.call(principal:, organization_id:, company_id: nil, branch_id: nil, &) = new(principal:, organization_id:, company_id:, branch_id:).call(&)

    def initialize(principal:, organization_id:, company_id:, branch_id:)
      @principal = principal
      @organization_id = organization_id
      @company_id = company_id
      @branch_id = branch_id
    end

    def call(&block)
      organization = Tenancy::Directory.organization!(identifier(@organization_id))
      Tenancy.with_context(organization:, principal: @principal) do
        @principal.activate!(organization.id)
        not_found! unless @principal.member?
        raise OrganizationSuspended, "La organización está suspendida" if organization.suspended?

        within_company_and_branch(organization, &block)
      end
    end

    private

    def within_company_and_branch(organization, &block)
      # Una sucursal sin empresa no es una ruta válida: se rechaza, no se ignora.
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

    # Un parámetro que no es una cadena (?organization_id[]=…) no es un id: mismo 404.
    def identifier(value) = value.is_a?(String) ? value : not_found!

    def not_found! = raise(ActiveRecord::RecordNotFound, "No se encontró el recurso")
  end
end
