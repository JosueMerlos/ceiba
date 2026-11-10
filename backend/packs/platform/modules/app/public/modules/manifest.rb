module Modules
  # Un módulo declarado (docs/architecture/05-module-system.md). Inmutable y ya validado: lo construye Modules::Registry#define
  # a partir del DSL de `Modules.define`; nadie más debería instanciarlo.
  #
  # Las referencias a código del módulo (`on_enable`, `on_disable`) son CADENAS, no constantes: la plataforma no conoce
  # ningún módulo estáticamente (packwerk, visible_to: []) y las resuelve con `constantize` al ejecutarlas.
  class Manifest < Data.define(
    :key, :name, :version, :requires, :platform, :permissions, :role_grants, :api_scopes, :settings_schema, :settings_levels,
    :publishes, :subscribes, :navigation, :on_enable, :on_disable, :schemer
  )
    Permission = Data.define(:key, :description)
    LEVELS = %w[company branch].freeze

    def permission_keys = permissions.map(&:key)

    # Valores por defecto del esquema: el piso de la resolución de settings.
    def defaults = settings_schema.fetch("properties").transform_values { |property| property.fetch("default") }

    def setting_keys = settings_schema.fetch("properties").keys

    # Niveles en los que se puede sobrescribir una clave: `x-levels` de la propiedad o, si no lo declara, todos los de
    # `settings_levels` del módulo.
    def levels_for(setting_key)
      settings_schema.dig("properties", setting_key, "x-levels") || settings_levels
    end

    def overridable_at?(level, setting_key) = levels_for(setting_key).include?(level.to_s)
  end
end
