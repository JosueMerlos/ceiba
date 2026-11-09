module Modules
  # Arma la respuesta de GET /api/v1/me: contexto elegido, módulos activos con settings resueltos, permisos y navegación.
  #
  # Elección del contexto: lo pedido por parámetros (explícito: si no es visible, 404/403 como cualquier ruta); si no, el último
  # recordado (Modules::ContextCookie) y, si no sirve (ya no hay acceso, organización suspendida), la primera organización del
  # usuario por id. Dentro de la organización, sin empresa pedida se toma la primera que el usuario ve (por id). Sin ningún
  # membership, el contexto queda vacío. Devuelve [payload, selección usada] (la selección es null con el contexto vacío).
  class Me
    EMPTY_CONTEXT = { organization: nil, company: nil, branch: nil }.freeze

    def self.call(...) = new(...).call

    def initialize(principal:, requested: nil, remembered: nil)
      @principal = principal
      @requested = requested
      @remembered = remembered
    end

    def call
      return build(@requested) if @requested

      candidates.each do |selection|
        return build(selection)
      rescue ActiveRecord::RecordNotFound, Access::OrganizationSuspended
        next # un contexto recordado o por defecto que ya no sirve no es un error del usuario
      end
      [ payload(EMPTY_CONTEXT, [], [], []), nil ]
    end

    private

    def candidates
      defaults = @principal.organization_ids.sort.map { |organization_id| ContextCookie::Selection.new(organization_id:, company_id: nil, branch_id: nil) }
      [ @remembered, *defaults ].compact.uniq
    end

    def build(selection)
      Access.with_context(
        principal: @principal, organization_id: selection.organization_id, company_id: selection.company_id,
        branch_id: selection.branch_id, read_only: true
      ) do |context|
        company = context.company || default_company
        next company_payload(context, company, selection) if context.company || company.nil?

        Tenancy.with_context(organization: context.organization, company:, branch: context.branch, principal: @principal) do |inner|
          company_payload(inner, company, selection)
        end
      end
    end

    # Sin empresa pedida: la primera que el usuario ve (permiso de leer la empresa, que todo membership tiene).
    def default_company
      reach = @principal.reach("platform.company.read")
      companies = Tenancy::Directory.companies.order(:id)
      reach.organization? ? companies.first : companies.where(id: reach.company_ids).first
    end

    def company_payload(context, company, selection)
      return [ payload({ organization: context.organization, company: nil, branch: nil }, [], [], []), selection_for(context, nil) ] unless company

      modules = ActiveModules.call(company:, branch: context.branch)
      permissions = @principal.permission_keys_in(company_id: company.id, branch_id: context.branch&.id)
      navigation = navigation_for(modules, permissions)
      [ payload({ organization: context.organization, company:, branch: context.branch }, modules, permissions, navigation), selection_for(context, company, selection) ]
    end

    def selection_for(context, company, _selection = nil)
      ContextCookie::Selection.new(organization_id: context.organization.id, company_id: company&.id, branch_id: context.branch&.id)
    end

    def navigation_for(modules, permissions)
      modules.flat_map do |entry|
        entry.manifest.navigation.select { |item| permissions.include?(item[:permission]) }
          .map { |item| { module: entry.manifest.key, key: item[:key], path: item[:path] } }
      end
    end

    def payload(context, modules, permissions, navigation)
      {
        principal: { id: @principal.id, name: @principal.full_name, email: @principal.email },
        context: {
          organization: context[:organization] && Tenancy::OrganizationSummarySerializer.new(context[:organization]).serializable_hash,
          company: context[:company] && Tenancy::CompanySerializer.new(context[:company]).serializable_hash,
          branch: context[:branch] && Tenancy::BranchSerializer.new(context[:branch]).serializable_hash
        },
        modules: modules.map { |entry| { key: entry.manifest.key, version: entry.manifest.version, settings: entry.settings } },
        permissions:, navigation:
      }
    end
  end
end
