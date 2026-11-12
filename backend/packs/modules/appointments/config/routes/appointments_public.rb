# Anonymous routes of the public booking surface, named by the company's slug. Mounted by config/routes.rb with
# `draw(:appointments_public)` under /api/public/v1.
get "c/:slug/availability", to: "appointments/availability#show"
