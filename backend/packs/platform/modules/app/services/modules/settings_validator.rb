module Modules
  # Valida un objeto de settings YA RESUELTO contra el JSON Schema del módulo y devuelve el detalle por campo
  # ([{ field:, code:, message: }], vacío si es válido). Los campos anidados se nombran con puntos (`reminders.0.offset_minutes`).
  module SettingsValidator
    JSON_TYPES = %w[string integer number boolean array object null].freeze

    module_function

    def call(manifest, settings)
      manifest.schemer.validate(settings.as_json).flat_map { |error| field_errors(error) }
    end

    def field_errors(error)
      pointer = error["data_pointer"].delete_prefix("/").tr("/", ".")
      return Array(error.dig("details", "missing_keys")).map { |missing| build([ pointer, missing ].reject(&:empty?).join("."), "required") } if error["type"] == "required"

      [ build(pointer, code_for(error["type"])) ]
    end

    # Un fallo de `type` llega como el tipo esperado ("boolean"); una propiedad no permitida, como "schema".
    def code_for(type)
      return "type" if JSON_TYPES.include?(type)
      return "unknown" if type == "schema"

      type
    end

    def build(field, code)
      { field:, code:, message: I18n.t("modules.settings_errors.#{code}", default: I18n.t("modules.settings_errors.invalid")) }
    end
  end
end
