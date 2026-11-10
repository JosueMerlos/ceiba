# Modules domain errors the API translates to problem+json (titles under api.errors.modules.* in the locale).
#
# - UnknownModule: the key is in no manifest (404; module keys are not secret).
# - NotEntitled: the plan does not include the module (403; never happens yet).
# - RequirementsNotMet / RequiredByOthers / NotEnabled: activation state forbids it (409); `detail` names the modules.
# - InvalidSettings: 422 with per-field `errors[]` ({ field, code, message }).
# An inactive module on its own routes does NOT use these codes: RequiresModule answers the generic 404 (resource.not_found).
Rails.application.config.to_prepare do
  registry = Api::ErrorRegistry

  registry.register(Modules::UnknownModule, status: :not_found, code: "modules.unknown_module", detail: ->(error) { error.message })
  registry.register(Modules::NotEntitled, status: :forbidden, code: "modules.not_entitled", detail: ->(error) { error.message })
  registry.register(Modules::RequirementsNotMet, status: :conflict, code: "modules.requirements_not_met", detail: ->(error) { error.message })
  registry.register(Modules::RequiredByOthers, status: :conflict, code: "modules.required_by_others", detail: ->(error) { error.message })
  registry.register(Modules::NotEnabled, status: :conflict, code: "modules.not_enabled", detail: ->(error) { error.message })
  registry.register(Modules::InvalidSettings, status: :unprocessable_content, code: "modules.invalid_settings", errors: ->(error) { error.errors })
end
