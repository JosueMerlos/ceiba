# Routes of the organization > company > branch hierarchy, mounted by config/routes.rb with `draw(:access)` under /api/v1.
# They live in access, not tenancy, because each one resolves against the principal's memberships (Access::Authorization).
# Read-only for now.
resources :organizations, only: %i[index show], controller: "access/organizations" do
  resources :companies, only: %i[index show], controller: "access/companies" do
    resources :branches, only: %i[index show], controller: "access/branches"
  end
end
