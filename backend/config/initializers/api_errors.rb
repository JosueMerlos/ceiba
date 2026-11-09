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
  # Errores de cliente que Rails ya clasifica: se registran para darles un code propio (el resto sale como http.<status>).
  registry.register(ActionController::UnknownHttpMethod, status: :method_not_allowed, code: "request.method_not_allowed")
  registry.register(ActionDispatch::Http::MimeNegotiation::InvalidType, status: :not_acceptable, code: "request.not_acceptable")
  registry.register(ActionController::UnknownFormat, status: :not_acceptable, code: "request.unknown_format")
  registry.register(ActionController::NotImplemented, status: :not_implemented, code: "request.not_implemented")
  registry.register(Api::QueryNotAllowed, status: :bad_request, code: "request.query_not_allowed")
  registry.register(Api::UnsupportedMediaType, status: :unsupported_media_type, code: "request.unsupported_media_type")
  registry.register(ActionController::BadRequest, status: :bad_request, code: "request.bad_request")
  registry.register(ActionDispatch::Http::Parameters::ParseError, status: :bad_request, code: "request.malformed")
end
