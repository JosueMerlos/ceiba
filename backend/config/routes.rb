Rails.application.routes.draw do
  # Todo vive bajo /api: el proxy no quita el prefijo, así desarrollo y producción coinciden (ADR-0013).
  scope path: "api" do
    get "health", to: "health#show"
    get "ready", to: "ready#show"

    # Swagger UI y el contrato versionado: solo desarrollo, test y staging (Api::Docs.enabled?).
    if Api::Docs.enabled?
      mount Rswag::Ui::Engine => "docs"
      mount Rswag::Api::Engine => "docs"
    end

    # API v1. Cada pack aporta sus controladores en Api::V1::<Pack> (docs/architecture/02-modular-monolith.md).
    scope path: "v1", module: "api/v1" do
      draw(:identity)
      draw(:tenancy)
    end
  end
end
