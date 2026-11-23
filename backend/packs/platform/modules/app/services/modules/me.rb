module Modules
  # Builds the GET /api/v1/me response: chosen context, active modules with resolved settings, permissions and navigation.
  #
  # `company_permissions` are the keys held at the COMPANY scope: unlike `permissions`, they leave out those that only apply
  # to a branch the user has a membership in, so the frontend can tell whether a company-wide route is open.
  #
  # Context choice: what the params request (explicit: if not visible, 404/403 like any route); else the remembered one
  # (Modules::ContextCookie) and, if unusable (access lost, organization suspended), the user's first organization by id.
  # Within the organization, without a requested company the first one the user sees (by id) is taken. With no membership the
  # context is empty. Returns [payload, selection used] (nil selection for an empty context).
  class Me
    EMPTY_CONTEXT = { organization: nil, company: nil, branch: nil }.freeze
    # Screens of the platform itself, available whatever modules the company has. Module manifests cannot declare platform
    # permissions, so these entries live here.
    PLATFORM_NAVIGATION = [ { key: "customers", path: "/customers", permission: "platform.customer.read" } ].freeze

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
        next # a stale remembered or default context is not a user error
      end
      [ payload(EMPTY_CONTEXT, [], [], [], []), nil ]
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

    # No company requested: the first one the user sees (company read permission, which every membership has).
    def default_company
      reach = @principal.reach("platform.company.read")
      companies = Tenancy::Directory.companies.order(:id)
      reach.organization? ? companies.first : companies.where(id: reach.company_ids).first
    end

    def company_payload(context, company, selection)
      return [ payload({ organization: context.organization, company: nil, branch: nil }, [], [], [], []), selection_for(context, nil) ] unless company

      modules = ActiveModules.call(company:, branch: context.branch)
      permissions = @principal.permission_keys_in(company_id: company.id, branch_id: context.branch&.id)
      company_permissions = @principal.company_permission_keys_in(company_id: company.id)
      navigation = navigation_for(modules, permissions)
      [ payload({ organization: context.organization, company:, branch: context.branch }, modules, permissions, navigation, company_permissions), selection_for(context, company, selection) ]
    end

    def selection_for(context, company, _selection = nil)
      ContextCookie::Selection.new(organization_id: context.organization.id, company_id: company&.id, branch_id: context.branch&.id)
    end

    def navigation_for(modules, permissions)
      platform = PLATFORM_NAVIGATION.select { permissions.include?(it[:permission]) }.map { { module: "platform", key: it[:key], path: it[:path] } }
      platform + modules.flat_map do |entry|
        entry.manifest.navigation.select { |item| Array(item[:permission]).intersect?(permissions) }
          .map { |item| { module: entry.manifest.key, key: item[:key], path: item[:path] } }
      end
    end

    def payload(context, modules, permissions, navigation, company_permissions)
      {
        principal: { id: @principal.id, name: @principal.full_name, email: @principal.email },
        context: {
          organization: context[:organization] && Tenancy::OrganizationSummarySerializer.new(context[:organization]).serializable_hash,
          company: context[:company] && Tenancy::CompanySerializer.new(context[:company]).serializable_hash,
          branch: context[:branch] && Tenancy::BranchSerializer.new(context[:branch]).serializable_hash
        },
        modules: modules.map { |entry| { key: entry.manifest.key, version: entry.manifest.version, settings: entry.settings } },
        permissions:, company_permissions:, navigation:
      }
    end
  end
end
