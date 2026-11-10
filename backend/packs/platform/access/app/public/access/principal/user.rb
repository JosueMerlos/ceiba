module Access
  module Principal
    # The person authenticated by a session, with the permissions their memberships give them IN THE ACTIVE ORGANIZATION.
    #
    # Request lifecycle: Access::RouteContext builds it from the identity (Identity::Principal::User), validates the route
    # and activates it (`activate!`) INSIDE Tenancy.with_context: that is the request's ONLY permissions query and it is
    # memoized. Afterwards `can?`, `reach`, `member?`... do not hit the database.
    #
    # It never queries on its own or crosses organizations: when inactive, or given a scope of another organization, it
    # denies (a user with memberships in X and Y only uses those of the route's organization).
    class User
      include Principal

      attr_reader :id, :email, :full_name, :organization_id

      # `identity_user`: any object with id, email and full_name (Identity::Principal::User).
      def initialize(identity_user)
        @id = identity_user.id
        @email = identity_user.email
        @full_name = identity_user.full_name
      end

      def kind = :user

      # Loads (one query) the user's memberships and permissions in `organization_id`. Requires being inside
      # Tenancy.with_context of THAT organization, so the tenant bounds the query and another organization's can't be loaded.
      def activate!(organization_id)
        current = ActsAsTenant.current_tenant&.id
        raise ArgumentError, "activate! exige Tenancy.with_context de la organización #{organization_id} (hay #{current.inspect})" unless current == organization_id

        @organization_id = organization_id
        @active_modules = nil # active modules belong to ONE organization: reactivating in another must not reuse the memo
        @grants = Grants.load(user_id: id, upward_keys: Access.registry.upward_keys, branch_company: ->(branch_id) { Tenancy::Directory.branch_company_id(branch_id) })
        self
      end

      def active? = !@grants.nil?

      def can?(permission_key, scope)
        Principal.ensure_registered!(permission_key)
        return false unless active? && scope.organization_id == organization_id
        return false unless module_allows?(permission_key, scope)

        @grants.allows?(permission_key, scope)
      end

      # Is `module_key` active in the company? Modules the gate does not control (platform) always are. Memoized per
      # principal (one query per request).
      def module_active?(module_key, company_id)
        return true unless Access.module_gate&.gated?(module_key.to_s)

        active_companies(module_key.to_s).include?(company_id)
      end

      # Permissions it holds in the context (company and/or branch) whose module is active in that company: what /me gives
      # the frontend to REFLECT (not decide) what to show. Without a company in the context there are no module permissions.
      def permission_keys_in(company_id: nil, branch_id: nil)
        return [] unless active?

        @grants.keys_within(company_id:, branch_id:).select { |key| Access.registered?(key) && module_active_in_context?(key, company_id) }.sort
      end

      def member? = active? && @grants.member?

      # Route visibility: does any membership contain this company / branch (or sit inside it)? Not authorization
      # (that is `can?`): it decides 404 (cannot see it) versus 403 (sees it but cannot act).
      def sees_company?(company_id) = active? && @grants.sees_company?(company_id)
      def sees_branch?(branch_id, company_id) = active? && @grants.sees_branch?(branch_id, company_id)

      # What resources of the active organization a permission reaches (Access::Reach), to filter listings.
      def reach(permission_key)
        Principal.ensure_registered!(permission_key)
        return Reach.new(organization: false, company_ids: [], branch_ids: []) unless active?

        restrict_to_active_modules(@grants.reach(permission_key), permission_key)
      end

      # Organizations where it has any membership (context selector). Crosses tenants ON PURPOSE: this is the only path and
      # it lives in Access::MembershipDirectory (cop Ceiba/TenantBypass, AllowedFiles). Memoized.
      def organization_ids = @organization_ids ||= MembershipDirectory.organization_ids_for(id)

      private

      def module_key_of(permission_key) = Access.registry.fetch(permission_key).module_key

      # A gated module's permission requires the module active in the scope's company (at organization scope, in any).
      def module_allows?(permission_key, scope)
        module_key = module_key_of(permission_key)
        return true unless Access.module_gate&.gated?(module_key)

        companies = active_companies(module_key)
        scope.company_id ? companies.include?(scope.company_id) : companies.any?
      end

      def module_active_in_context?(permission_key, company_id)
        module_key = module_key_of(permission_key)
        return true unless Access.module_gate&.gated?(module_key)

        company_id.present? && active_companies(module_key).include?(company_id)
      end

      # A module's listing only reaches companies where it is active: organization scope becomes "those companies".
      def restrict_to_active_modules(reach, permission_key)
        module_key = module_key_of(permission_key)
        return reach unless Access.module_gate&.gated?(module_key)

        active = active_companies(module_key)
        return Reach.new(organization: false, company_ids: active.to_a, branch_ids: []) if reach.organization?

        Reach.new(
          organization: false, company_ids: reach.company_ids & active.to_a,
          branch_ids: reach.branch_ids.select { |branch_id| active.include?(@grants.branch_company_id(branch_id)) }
        )
      end

      # { module => Set[companies] }: ONE query (the gate's) per principal. Without a tenancy context it cannot be known:
      # deny (empty set) and do NOT memoize the failure.
      def active_companies(module_key)
        @active_modules ||= Access.module_gate.active_companies_by_module
        @active_modules.fetch(module_key, Set.new)
      rescue ActsAsTenant::Errors::NoTenantSet
        Set.new
      end
    end
  end
end
