# Rutas de la jerarquía organización > empresa > sucursal, montadas por config/routes.rb con `draw(:access)` bajo /api/v1
# (docs/architecture/02). Viven en access y no en tenancy porque cada una se resuelve contra los memberships del principal
# (Access::Authorization). Solo lectura en M0.08; las escrituras llegan con M4.01.
resources :organizations, only: %i[index show], controller: "access/organizations" do
  resources :companies, only: %i[index show], controller: "access/companies" do
    resources :branches, only: %i[index show], controller: "access/branches"
  end
end
