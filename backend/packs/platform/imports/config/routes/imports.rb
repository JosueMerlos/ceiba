# CSV imports of a company's data, uploaded from the branch the staff acts from (like customers, the route carries the
# branch). Mounted by config/routes.rb with `draw(:imports)` under /api/v1. Member params are named, never :id.
scope path: "organizations/:organization_id/companies/:company_id/branches/:branch_id" do
  post "imports", to: "imports/imports#create"
  get "imports/:import_id", to: "imports/imports#show"
  get "imports/:import_id/rows", to: "imports/imports#rows"
  post "imports/:import_id/confirm", to: "imports/imports#confirm"
end
