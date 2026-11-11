# Services are company records; an override belongs to a branch of that company. Mounted by config/routes.rb with
# `draw(:appointments)` under /api/v1. Updates are PATCH only (resources would also draw PUT).
scope path: "organizations/:organization_id/companies/:company_id/appointments" do
  resources :services, only: %i[index show create destroy], controller: "appointments/services"
  patch "services/:id", to: "appointments/services#update"

  put "branches/:branch_id/services/:service_id/override", to: "appointments/service_overrides#upsert"
  delete "branches/:branch_id/services/:service_id/override", to: "appointments/service_overrides#destroy"
end

# Professionals are company records; their branch assignment lives under the branch. The member param is named
# (:professional_id), never :id, so the module coverage suite can build the right record for each route.
scope path: "organizations/:organization_id/companies/:company_id/appointments" do
  resources :professionals, only: %i[index show create destroy], param: :professional_id, controller: "appointments/professionals"
  patch "professionals/:professional_id", to: "appointments/professionals#update"
  put "professionals/:professional_id/services", to: "appointments/professional_services#update"

  # A professional's profile seen from a branch: the route a professional uses to read their own profile.
  get "branches/:branch_id/professionals/:professional_id", to: "appointments/professionals#show_in_branch"
  put "branches/:branch_id/professionals/:professional_id/assignment", to: "appointments/professional_assignments#upsert"
  delete "branches/:branch_id/professionals/:professional_id/assignment", to: "appointments/professional_assignments#destroy"
end
