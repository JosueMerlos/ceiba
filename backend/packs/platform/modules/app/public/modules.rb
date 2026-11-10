# Public API of the platform/modules pack. Business modules are DECLARED with `Modules.define` from their `manifest.rb`;
# the platform discovers them by file and never references their constants.
module Modules
  class << self
    # Called from `packs/modules/<key>/manifest.rb`. During Modules.load! it goes to the registry being built and takes the
    # pack as `root`; outside it (specs) it goes to the global registry and registers its permissions in access.
    def define(key, root: nil, &block)
      loading = Loader.current
      return loading[:registry].define(key, root: root || loading[:root], &block) if loading

      registry.define(key, root:, &block).tap { |manifest| AccessRegistration.call(manifest) }
    end

    def registry = @registry ||= Registry.new

    # `company` is the record or its id; must run inside Tenancy.with_context.
    def enabled?(company, key)
      CompanyModule.active.exists?(company_id: company.respond_to?(:id) ? company.id : company, module_key: key.to_s)
    end

    # Resolved settings: schema default -> company -> branch (when given). Raises NotEnabled if the module is inactive, and
    # InvalidSettings if stored values no longer satisfy the schema. Returns a new Hash; must run inside Tenancy.with_context.
    def settings_for(key, company:, branch: nil)
      raise ArgumentError, "la sucursal #{branch.id} no es de la empresa #{company.id}" if branch && branch.company_id != company.id

      manifest = registry.fetch(key)
      company_row = CompanyModule.active.find_by(company_id: company.id, module_key: manifest.key) or raise NotEnabled, manifest.key
      branch_settings = branch && BranchModuleSetting.find_by(branch_id: branch.id, module_key: manifest.key)&.settings
      SettingsResolver.call!(manifest, company_row.settings, branch_settings)
    end

    # Until plan entitlements exist, every plan is entitled to everything: enabling only requires `requires`.
    def entitled?(_company, _key) = true

    # A Flipper flag never replaces module activation (Modules::Enable) or an entitlement. `organization` is the record or its id.
    def flag_enabled?(feature, organization:)
      Flipper.enabled?(feature, FlagActor.new(organization.respond_to?(:id) ? organization.id : organization))
    end

    # Modules enabled when provisioning an organization; every plan includes `appointments` until plans drive this.
    def default_keys = %w[appointments]

    # Runs at boot and on every code reload: an invalid manifest FAILS the boot with a clear message.
    def load!(root: Rails.root)
      fresh = Loader.call(root:, registry: Registry.new)
      fresh.each { |manifest| AccessRegistration.call(manifest) }
      Access.module_gate = AccessGate
      @registry = fresh
    end
  end
end
