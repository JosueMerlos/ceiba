namespace :modules do
  desc "Valida los manifiestos y sincroniza sus permisos y role_grants con la base (Access.sync!, idempotente). Paso de release"
  # Los manifiestos se cargan y validan al arrancar el proceso (environment); los permisos viajan por el registro de access, así que
  # la sincronización es la de access (con sus salvaguardas: registro vacío, retiradas con ACCESS_SYNC_ALLOW_PRUNE=1, candado).
  task sync: %w[environment access:sync] do
    puts "Módulos sincronizados: #{Modules.registry.keys.join(', ')} (#{Modules.registry.all.sum { |manifest| manifest.permissions.size }} permisos)"
  end
end
