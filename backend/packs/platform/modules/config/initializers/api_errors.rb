# Errores de dominio de modules que la API traduce a problem+json (ver Api::ErrorRegistry; títulos en api.errors.modules.* del locale).
#
# - UnknownModule: la key no existe en ningún manifiesto (404; las keys de módulos no son secretas).
# - NotEntitled: el plan no incluye el módulo (403; hoy nunca ocurre, F6).
# - RequirementsNotMet / RequiredByOthers / NotEnabled: el estado de las activaciones lo impide (409); `detail` dice cuáles módulos.
# - InvalidSettings: 422 con `errors[]` por campo ({ field, code, message }).
# Un módulo inactivo en las rutas del propio módulo NO usa estos códigos: RequiresModule responde el 404 genérico (resource.not_found).
Rails.application.config.to_prepare do
  registry = Api::ErrorRegistry

  registry.register(Modules::UnknownModule, status: :not_found, code: "modules.unknown_module", detail: ->(error) { error.message })
  registry.register(Modules::NotEntitled, status: :forbidden, code: "modules.not_entitled", detail: ->(error) { error.message })
  registry.register(Modules::RequirementsNotMet, status: :conflict, code: "modules.requirements_not_met", detail: ->(error) { error.message })
  registry.register(Modules::RequiredByOthers, status: :conflict, code: "modules.required_by_others", detail: ->(error) { error.message })
  registry.register(Modules::NotEnabled, status: :conflict, code: "modules.not_enabled", detail: ->(error) { error.message })
  registry.register(Modules::InvalidSettings, status: :unprocessable_content, code: "modules.invalid_settings", errors: ->(error) { error.errors })
end
