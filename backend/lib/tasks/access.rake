namespace :access do
  desc "Sincroniza permisos, roles de sistema y role_permissions desde el registro de los packs (idempotente). Retirar permisos exige ACCESS_SYNC_ALLOW_PRUNE=1"
  task sync: :environment do
    Access.sync!
    puts "Catálogo de acceso sincronizado: #{Access.permission_keys.size} permisos, #{Access::SYSTEM_ROLES.size} roles de sistema"
  end
end

# Every deploy migrates and then syncs the catalog. If the table does not exist yet (migrating to a version before the
# access catalog) there is nothing to sync. db:prepare does NOT invoke db:migrate (it migrates on its own), so it is
# chained too.
%w[db:migrate db:prepare].each do |task|
  Rake::Task[task].enhance do
    Rake::Task["access:sync"].invoke if ActiveRecord::Base.connection.table_exists?("roles")
  end
end
