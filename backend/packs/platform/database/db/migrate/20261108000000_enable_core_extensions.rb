# PostgreSQL extensions used across the product:
#   btree_gist  exclusion constraints that combine = and && (schedule integrity)
#   citext      case-insensitive emails and slugs
# Both are "trusted", so app_owner can create them without superuser. pg_stat_statements is NOT enabled here
# (it needs superuser and preloading); see infra/db/init-roles.sh.
class EnableCoreExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist"
    enable_extension "citext"
  end
end
