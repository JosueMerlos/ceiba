module Api
  # Swagger UI y el contrato en /api/docs: solo en desarrollo y test, y en staging si lo activa API_DOCS_ENABLED=true
  # (staging corre con RAILS_ENV=production). En producción no existen las rutas
  # (docs/architecture/07-api-contract.md).
  module Docs
    def self.enabled?(environment: Rails.env, flag: ENV.fetch("API_DOCS_ENABLED", nil))
      %w[development test].include?(environment.to_s) || flag == "true"
    end
  end
end
