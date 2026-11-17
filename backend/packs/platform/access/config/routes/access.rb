# Routes of the organization > company > branch hierarchy, mounted by config/routes.rb with `draw(:access)` under /api/v1.
# They live in access, not tenancy, because each one resolves against the principal's memberships (Access::Authorization).
# Read-only, except a company's branding (GET and PATCH, multipart).
resources :organizations, only: %i[index show], controller: "access/organizations" do
  resources :companies, only: %i[index show], controller: "access/companies" do
    # PATCH only (no PUT): it is the one method the request guard lets carry multipart.
    resource :branding, only: :show, controller: "access/brandings"
    patch "branding", to: "access/brandings#update"
    resources :branches, only: %i[index show], controller: "access/branches"
  end
end
