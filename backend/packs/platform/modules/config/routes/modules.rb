# Rutas de platform/modules, montadas por config/routes.rb con `draw(:modules)` bajo /api/v1.
get "me", to: "modules/me#show"

# Activar/desactivar un módulo de una empresa y escribir sus settings (platform.company_module.manage). Los settings de una sucursal
# cuelgan de la sucursal de la ruta: la API no admite query string en las mutaciones (Api::RequestGuard) y así Access::Authorization
# valida la sucursal (404 si no se ve) igual que cualquier otra ruta.
scope path: "organizations/:organization_id/companies/:company_id", controller: "modules/company_modules" do
  put "modules/:key", action: :update
  patch "modules/:key/settings", action: :update_settings
  patch "branches/:branch_id/modules/:key/settings", action: :update_branch_settings
end
