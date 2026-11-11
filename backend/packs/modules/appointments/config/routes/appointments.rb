# Services are company records; an override belongs to a branch of that company. Mounted by config/routes.rb with
# `draw(:appointments)` under /api/v1. Updates are PATCH only (resources would also draw PUT).
scope path: "organizations/:organization_id/companies/:company_id/appointments" do
  resources :services, only: %i[index show create destroy], controller: "appointments/services"
  patch "services/:id", to: "appointments/services#update"

  put "branches/:branch_id/services/:service_id/override", to: "appointments/service_overrides#upsert"
  delete "branches/:branch_id/services/:service_id/override", to: "appointments/service_overrides#destroy"
end
