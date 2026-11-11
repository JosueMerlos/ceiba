# Customers belong to a company but are managed from the branch the staff acts from: the route carries the branch, access
# is decided at branch scope and the listing shows the whole company's customers. Mounted by config/routes.rb with
# `draw(:customers)` under /api/v1.
scope path: "organizations/:organization_id/companies/:company_id/branches/:branch_id" do
  resources :customers, only: %i[index show create destroy], controller: "customers/customers"
  patch "customers/:id", to: "customers/customers#update"
end
