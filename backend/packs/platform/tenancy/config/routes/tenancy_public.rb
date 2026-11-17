# Anonymous routes of a company's public identity, named by its slug. Mounted by config/routes.rb with `draw(:tenancy_public)`
# under /api/public/v1.
get "c/:slug/branding", to: "tenancy/brandings#show"
