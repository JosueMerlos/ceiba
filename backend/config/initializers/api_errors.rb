# Errores "de plataforma" que toda la API traduce igual (docs/architecture/07-api-contract.md). Los errores de dominio
# de cada pack se registran en el initializer del propio pack (packs/*/*/config/initializers/api_errors.rb).
# `to_prepare` vuelve a registrar tras cada recarga de código en desarrollo.
Rails.application.config.to_prepare do
  registry = Api::ErrorRegistry

  registry.register(ActionController::RoutingError, status: :not_found, code: "route.not_found")
  registry.register(ActiveRecord::RecordNotFound, status: :not_found, code: "resource.not_found")

  registry.register(ActiveRecord::RecordInvalid, status: :unprocessable_content, code: "validation.failed",
    errors: ->(error) { Api::FieldErrors.from_record(error.record) })

  registry.register(ActiveRecord::StaleObjectError, status: :conflict, code: "resource.stale")
  registry.register(ActiveRecord::RecordNotUnique, status: :conflict, code: "resource.conflict")

  registry.register(ActionController::ParameterMissing, status: :bad_request, code: "request.invalid",
    errors: ->(error) { [ { field: error.param.to_s, code: "missing", message: I18n.t("errors.messages.blank") } ] })
  registry.register(Api::Pagination::InvalidCursor, status: :bad_request, code: "pagination.invalid_cursor")
  registry.register(Api::Pagination::InvalidLimit, status: :bad_request, code: "pagination.invalid_limit")
  registry.register(ActionController::BadRequest, status: :bad_request, code: "request.bad_request")
  registry.register(ActionDispatch::Http::Parameters::ParseError, status: :bad_request, code: "request.malformed")
end
