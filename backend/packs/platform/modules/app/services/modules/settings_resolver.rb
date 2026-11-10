module Modules
  # default del esquema -> empresa -> sucursal (docs/architecture/05-module-system.md). La sucursal solo sobrescribe las claves
  # que el esquema permite a ese nivel (`x-levels`/`settings_levels`): lo demás que traiga su fila se ignora. Devuelve un Hash
  # NUEVO (copia profunda): quien lo reciba puede modificarlo sin tocar el manifiesto.
  module SettingsResolver
    module_function

    def call(manifest, company_settings, branch_settings = nil)
      resolved = manifest.defaults.merge(company_settings.to_h.slice(*manifest.setting_keys))
      resolved = resolved.merge(branch_settings.to_h.slice(*branch_keys(manifest))) if branch_settings
      resolved.deep_dup
    end

    # Resuelve y VALIDA: lanza InvalidSettings si el resultado no cumple el esquema (datos guardados antes de un cambio incompatible).
    def call!(manifest, company_settings, branch_settings = nil)
      resolved = call(manifest, company_settings, branch_settings)
      errors = SettingsValidator.call(manifest, resolved)
      raise InvalidSettings.new(manifest.key, errors) if errors.any?

      resolved
    end

    def branch_keys(manifest) = manifest.setting_keys.select { |key| manifest.overridable_at?(:branch, key) }
  end
end
