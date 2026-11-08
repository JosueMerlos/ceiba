Rails.application.routes.draw do
  # Todo vive bajo /api: el proxy no quita el prefijo, así desarrollo y producción coinciden (ADR-0013).
  scope path: "api" do
    get "health", to: "health#show"
    get "ready", to: "ready#show"
  end
end
