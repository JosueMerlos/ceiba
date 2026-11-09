namespace :access do
  desc "Sincroniza permisos, roles de sistema y role_permissions desde el registro de los packs (idempotente). Retirar permisos exige ACCESS_SYNC_ALLOW_PRUNE=1"
  task sync: :environment do
    Access.sync!
    puts "Catálogo de acceso sincronizado: #{Access.permission_keys.size} permisos, #{Access::SYSTEM_ROLES.size} roles de sistema"
  end
end

# Cada despliegue migra y luego sincroniza el catálogo (ADR-0008: "sincronizar permisos al desplegar"). Si la tabla aún no
# existe (migrar hacia una versión anterior a M0.08) no hay nada que sincronizar.
# db:prepare NO invoca db:migrate (migra por su cuenta), así que se encadena también.
%w[db:migrate db:prepare].each do |task|
  Rake::Task[task].enhance do
    Rake::Task["access:sync"].invoke if ActiveRecord::Base.connection.table_exists?("roles")
  end
end
