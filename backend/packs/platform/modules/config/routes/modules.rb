# Rutas de platform/modules, montadas por config/routes.rb con `draw(:modules)` bajo /api/v1.
get "me", to: "modules/me#show"
