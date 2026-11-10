get "me", to: "modules/me#show"

# Branch settings hang from the route's branch: the API accepts no query string on mutations (Api::RequestGuard), and this way
# Access::Authorization validates the branch (404 if not visible) like any other route.
scope path: "organizations/:organization_id/companies/:company_id", controller: "modules/company_modules" do
  put "modules/:key", action: :update
  patch "modules/:key/settings", action: :update_settings
  patch "branches/:branch_id/modules/:key/settings", action: :update_branch_settings
end
