# Identity pack routes, mounted by config/routes.rb with `draw(:identity)` under /api/v1.
scope path: "auth" do
  post "login", to: "identity/sessions#create"
  get "session", to: "identity/sessions#show"
  delete "logout", to: "identity/sessions#destroy"
  delete "sessions", to: "identity/sessions#destroy_all"
end
