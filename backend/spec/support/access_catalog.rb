# Access control catalog (permissions and system roles) synced ONCE when the suite boots. It is platform data (global
# tables), not per-example: specs use it as in production after `Access.sync!`. Tests of the sync itself run it inside
# the example's transaction (rolled back).
#
# The FICTITIOUS modules (`sample*`, spec/support/sample_module.rb) do NOT go to this shared database: a separate
# process (the `access:sync` and `modules:sync` tasks some specs launch) does not know them and would refuse to "retire"
# them. Specs that use them sync them INSIDE their transaction with the "with the sample module synced" shared context.
module AccessCatalogSuite
  module_function

  # The real registry: everything registered except the fictitious modules.
  def registry_without_samples
    Access::PermissionRegistry.new.tap do |registry|
      Access.registry.definitions.reject { |definition| definition.module_key.start_with?("sample") }.group_by(&:module_key).each do |module_key, definitions|
        registry.register(module_key, definitions.to_h { |definition| [ definition.key, { description: definition.description, roles: definition.roles, from_descendants: definition.from_descendants } ] })
      end
    end
  end
end

RSpec.configure do |config|
  # allow_prune: the suite may boot with a catalog that a previous run left modified.
  config.before(:suite) { Access.sync!(AccessCatalogSuite.registry_without_samples, allow_prune: true) }
end

# Brings `sample` and `sample_addon` permissions into the database (inside the example's transaction).
RSpec.shared_context "con el módulo sample sincronizado" do
  before { Access.sync!(allow_prune: true) }
end
