# Extensiones de PostgreSQL que usa todo el producto (docs/architecture/09-data-conventions.md):
#   btree_gist  exclusion constraints que combinan = y && (integridad de agenda, ADR-0018)
#   citext      correos y slugs sin distinguir mayúsculas
# Ambas son "trusted": las puede crear app_owner sin ser superusuario. pg_stat_statements NO va aquí
# (exige superusuario y precarga): ver infra/db/init-roles.sh.
class EnableCoreExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist"
    enable_extension "citext"
  end
end
