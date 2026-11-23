# The ONLY Active Storage route: the GET proxy of an already rendered variant (see Tenancy::Storage::RepresentationsController). Mounted
# by config/routes.rb with `draw(:tenancy_storage)` under /api/storage. Active Storage's own routes stay off
# (`draw_routes = false`): no direct uploads, no disk PUT, no route for an original. Drawn by hand, so the named helper that
# builds the URLs is declared here.
get "representations/proxy/:signed_blob_id/:variation_key/*filename", to: "tenancy/storage/representations#show", as: :rails_blob_representation_proxy
