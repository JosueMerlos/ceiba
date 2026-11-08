Rails.application.routes.draw do
  # Todo vive bajo /api: el proxy no quita el prefijo, así desarrollo y producción coinciden (ADR-0013).
  scope path: "api" do
    get "health", to: "health#show"
    get "ready", to: "ready#show"

    # API v1. Cada pack aporta sus controladores en Api::V1::<Pack> (docs/architecture/02-modular-monolith.md).
    scope path: "v1", module: "api/v1" do
      resources :organizations, only: :show, controller: "tenancy/organizations"
    end
  end
end
