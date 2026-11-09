# Swagger UI y servidor del contrato (rswag-api / rswag-ui), montados en /api/docs solo donde Api::Docs.enabled?
# (config/routes.rb). El contrato es openapi/v1.yaml, generado por `bin/rails openapi:generate`.
Rswag::Api.configure do |config|
  config.openapi_root = Rails.root.join("openapi").to_s
end

Rswag::Ui.configure do |config|
  config.openapi_endpoint "/api/docs/v1.yaml", "Ceiba API v1"
end
