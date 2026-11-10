namespace :modules do
  desc "Valida los manifiestos y sincroniza sus permisos y role_grants con la base (Access.sync!, idempotente). Paso de release"
  # Manifests are loaded and validated when the process boots (environment); permissions travel through the access
  # registry, so syncing is access's (with its safeguards: empty registry, removals need ACCESS_SYNC_ALLOW_PRUNE=1, lock).
  task sync: %w[environment access:sync] do
    puts "Módulos sincronizados: #{Modules.registry.keys.join(', ')} (#{Modules.registry.all.sum { |manifest| manifest.permissions.size }} permisos)"
  end
end
