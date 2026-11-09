# Rutas del pack tenancy, montadas por config/routes.rb con `draw(:tenancy)` bajo /api/v1 (docs/architecture/02).
# Endpoint de ejemplo de M0.06: temporalmente sin autenticación (ver Api::V1::Tenancy::OrganizationsController).
resources :organizations, only: :show, controller: "tenancy/organizations"
