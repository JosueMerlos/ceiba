module Modules
  # Schema default -> company -> branch. The branch only overrides keys the schema allows at that level (`x-levels`/
  # `settings_levels`); anything else in its row is ignored. Returns a NEW Hash (deep copy), safe to mutate without touching
  # the manifest.
  module SettingsResolver
    module_function

    def call(manifest, company_settings, branch_settings = nil)
      resolved = manifest.defaults.merge(company_settings.to_h.slice(*manifest.setting_keys))
      resolved = resolved.merge(branch_settings.to_h.slice(*branch_keys(manifest))) if branch_settings
      resolved.deep_dup
    end

    # Resolves and VALIDATES: raises InvalidSettings if the result breaks the schema (data stored before an incompatible change).
    def call!(manifest, company_settings, branch_settings = nil)
      resolved = call(manifest, company_settings, branch_settings)
      errors = SettingsValidator.call(manifest, resolved)
      raise InvalidSettings.new(manifest.key, errors) if errors.any?

      resolved
    end

    def branch_keys(manifest) = manifest.setting_keys.select { |key| manifest.overridable_at?(:branch, key) }
  end
end
