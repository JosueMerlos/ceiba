Rails.application.routes.draw do
  # Everything lives under /api: the proxy does not strip the prefix, so development and production match.
  # format: false because the API takes no format extension (/login.json would dodge the per-path Rack::Attack rules).
  scope path: "api", format: false do
    get "health", to: "health#show"
    get "ready", to: "ready#show"

    # Swagger UI and the versioned contract: development, test and staging only.
    if Api::Docs.enabled?
      mount Rswag::Ui::Engine => "docs"
      mount Rswag::Api::Engine => "docs"
    end

    # API v1. Each pack contributes its controllers under Api::V1::<Pack>.
    scope path: "v1", module: "api/v1" do
      draw(:identity)
      draw(:access)
      draw(:modules)
      draw(:customers)
      draw(:appointments)
    end

    # Public API v1: anonymous, by company slug. Each pack contributes its controllers under Api::Public::V1::<Pack>.
    scope path: "public/v1", module: "api/public/v1" do
      draw(:appointments_public)
    end
  end
end
