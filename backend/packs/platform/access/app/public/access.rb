# Public API of the platform/access pack. The rest of the app declares permissions with `Access.register_permissions`,
# authorizes with `Access::BasePolicy` and `Access::Authorization`, and grants roles with `Access::GrantRole`;
# the pack's models are private.
module Access
  # System roles (platform templates) and their scope: the closed catalog of role keys allowed in a permission
  # declaration. POLICIES never use them (cop Ceiba/AccessPolicyRoles).
  SYSTEM_ROLES = {
    "org_owner" => "organization",
    "org_admin" => "organization",
    "company_manager" => "company",
    "branch_manager" => "branch",
    "receptionist" => "branch",
    "professional" => "branch"
  }.freeze

  # READ actions: the only ones `from_descendants` applies to (upward reading never grants writing). Public so callers can
  # list them in their error messages.
  READ_ACTIONS = %w[read list show view].freeze

  class << self
    # Whether a <module>.<resource>.<action> key names a READ action. One predicate, so the manifest validator rejects the
    # same declarations the permission registry does.
    def read_permission?(key) = READ_ACTIONS.include?(key.split(".").last)

    # Declares a module's permissions and which system roles receive them (the role matrix as DATA). Call it from
    # `config.to_prepare` in the pack's initializer so it survives code reloading in development:
    #
    #   Rails.application.config.to_prepare do
    #     Access.register_permissions("appointments",
    #       "appointments.appointment.create" => { description: "Crear citas", roles: %w[company_manager branch_manager receptionist] })
    #   end
    #
    # `from_descendants: true` is only for READ permissions on a higher scope (e.g. reading the company) that a branch
    # membership also exercises on the company its branch belongs to. It does not cover sibling branches.
    #
    # Keys follow <module>.<resource>.<action> and start with the declaring module. Raises ArgumentError on an invalid
    # declaration (malformed key, foreign prefix, unknown role, key repeated in another module). A permission a policy
    # uses but nobody registered fails the suite (Access::BasePolicy#can? raises and a spec scans every pack's policies).
    def register_permissions(module_key, permissions)
      registry.register(module_key, permissions)
    end

    def permission_keys = registry.keys

    def registered?(key) = registry.registered?(key)

    # Writes the registry to the database: permissions, system roles and role_permissions. Idempotent; runs on every
    # deploy (chained by db:migrate and db:prepare, run by db:seed), never at process boot.
    #
    # Safety net (raises Access::SyncRefused WITHOUT changing anything): an empty registry (a process that did not load the
    # packs must not "delete everything") and any removal of permissions or grants, which requires `allow_prune: true` or
    # ACCESS_SYNC_ALLOW_PRUNE=1. Only ADDING never needs authorization. An advisory transaction lock serializes
    # concurrent deploys.
    def sync!(registry = self.registry, allow_prune: ENV["ACCESS_SYNC_ALLOW_PRUNE"] == "1") = CatalogSync.call(registry, allow_prune:)

    # Opens the context (organization and optionally company and branch) for a principal and validates it against its
    # memberships, like a nested route (Access::RouteContextResolver): 404 if not visible, 403 if the organization is
    # suspended. For endpoints that carry no context in the route, such as GET /api/v1/me. Yields the Tenancy::Context;
    # with `read_only: true` the transaction is read-only.
    def with_context(principal:, organization_id:, company_id: nil, branch_id: nil, read_only: false, &)
      RouteContextResolver.call(principal:, organization_id:, company_id:, branch_id:, read_only:, &)
    end

    # Extension point for MODULES: besides the membership, a module's permission requires that module to be ACTIVE in the
    # resource's company. access does not know platform/modules (modules depends on access, a cycle would not validate),
    # so modules registers itself here at boot. A gate answers:
    #
    #   gated?(module_key)               is it an activatable business module? (`platform.*` permissions are not)
    #   active_companies_by_module       { "appointments" => Set[company_id, ...] } of the active organization (ONE query)
    #
    # Without a gate (nil) permissions are granted by membership alone. The principal asks for
    # `active_companies_by_module` once and memoizes it.
    attr_accessor :module_gate

    def registry = @registry ||= PermissionRegistry.new
  end
end
