module Modules
  # A declared module, immutable and already validated. Built by Modules::Registry#define from the `Modules.define` DSL;
  # nothing else should instantiate it.
  #
  # Code references (`on_enable`, `on_disable`) are STRINGS, not constants: the platform knows no module statically
  # (packwerk, visible_to: []) and resolves them with `constantize` when run.
  class Manifest < Data.define(
    :key, :name, :version, :requires, :platform, :permissions, :role_grants, :api_scopes, :settings_schema, :settings_levels,
    :publishes, :subscribes, :navigation, :on_enable, :on_disable, :schemer
  )
    Permission = Data.define(:key, :description)
    LEVELS = %w[company branch].freeze

    def permission_keys = permissions.map(&:key)

    # Schema defaults: the floor of settings resolution.
    def defaults = settings_schema.fetch("properties").transform_values { |property| property.fetch("default") }

    def setting_keys = settings_schema.fetch("properties").keys

    # Levels where a key can be overridden: the property's `x-levels`, else all of the module's `settings_levels`.
    def levels_for(setting_key)
      settings_schema.dig("properties", setting_key, "x-levels") || settings_levels
    end

    def overridable_at?(level, setting_key) = levels_for(setting_key).include?(level.to_s)
  end
end
