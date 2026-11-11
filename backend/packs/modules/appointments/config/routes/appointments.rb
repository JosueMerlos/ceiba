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

# Resources, weekly hours and absences hang from a BRANCH: the permission is asked there and the owner (an assigned
# professional, the branch's resource) is searched among the branch's. `owner_kind` is a route default (a client cannot send
# it) that tells the shared controllers which owner the URL names. Member params are named, never :id.
scope path: "organizations/:organization_id/companies/:company_id/appointments" do
  put "services/:service_id/resource_requirements", to: "appointments/resource_requirements#update"

  scope path: "branches/:branch_id" do
    get "resources", to: "appointments/resources#index"
    post "resources", to: "appointments/resources#create"
    get "resources/:resource_id", to: "appointments/resources#show"
    patch "resources/:resource_id", to: "appointments/resources#update"
    delete "resources/:resource_id", to: "appointments/resources#destroy"

    get "schedule", to: "appointments/schedules#show", defaults: { owner_kind: "branch" }
    put "schedule", to: "appointments/schedules#update", defaults: { owner_kind: "branch" }
    get "professionals/:professional_id/schedule", to: "appointments/schedules#show", defaults: { owner_kind: "professional" }
    put "professionals/:professional_id/schedule", to: "appointments/schedules#update", defaults: { owner_kind: "professional" }
    get "resources/:resource_id/schedule", to: "appointments/schedules#show", defaults: { owner_kind: "resource" }
    put "resources/:resource_id/schedule", to: "appointments/schedules#update", defaults: { owner_kind: "resource" }

    get "professionals/:professional_id/time_offs", to: "appointments/time_offs#index", defaults: { owner_kind: "professional" }
    post "professionals/:professional_id/time_offs", to: "appointments/time_offs#create", defaults: { owner_kind: "professional" }
    delete "professionals/:professional_id/time_offs/:professional_time_off_id", to: "appointments/time_offs#destroy", defaults: { owner_kind: "professional" }
    get "resources/:resource_id/time_offs", to: "appointments/time_offs#index", defaults: { owner_kind: "resource" }
    post "resources/:resource_id/time_offs", to: "appointments/time_offs#create", defaults: { owner_kind: "resource" }
    delete "resources/:resource_id/time_offs/:resource_time_off_id", to: "appointments/time_offs#destroy", defaults: { owner_kind: "resource" }
  end
end
