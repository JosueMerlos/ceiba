# Rutas del pack identity, montadas por config/routes.rb con `draw(:identity)` bajo /api/v1 (docs/architecture/02).
scope path: "auth" do
  post "login", to: "identity/sessions#create"
  get "session", to: "identity/sessions#show"
  delete "logout", to: "identity/sessions#destroy"
  delete "sessions", to: "identity/sessions#destroy_all"
end
