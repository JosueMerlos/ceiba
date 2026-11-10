# Catálogo de control de acceso (permisos y roles de sistema) sincronizado UNA vez al arrancar la suite. Son datos de
# plataforma (tablas globales), no de un ejemplo: los specs los usan igual que en producción tras `Access.sync!`.
# Los tests que prueban la sincronización la ejecutan dentro de la transacción del ejemplo (se revierte).
#
# Los módulos FICTICIOS (`sample*`, spec/support/sample_module.rb) NO viajan a esta base compartida: un proceso aparte (las tareas
# `access:sync` y `modules:sync` que algunos specs lanzan) no los conoce y se negaría a "retirarlos". Los specs que los usan los
# sincronizan DENTRO de su transacción con el contexto compartido "con el módulo sample sincronizado".
module AccessCatalogSuite
  module_function

  # El registro real: todo lo registrado salvo los módulos ficticios.
  def registry_without_samples
    Access::PermissionRegistry.new.tap do |registry|
      Access.registry.definitions.reject { |definition| definition.module_key.start_with?("sample") }.group_by(&:module_key).each do |module_key, definitions|
        registry.register(module_key, definitions.to_h { |definition| [ definition.key, { description: definition.description, roles: definition.roles, from_descendants: definition.from_descendants } ] })
      end
    end
  end
end

RSpec.configure do |config|
  # allow_prune: la suite puede arrancar con un catálogo que una ejecución anterior dejó modificado.
  config.before(:suite) { Access.sync!(AccessCatalogSuite.registry_without_samples, allow_prune: true) }
end

# Lleva a la base (dentro de la transacción del ejemplo) los permisos de `sample` y `sample_addon`.
RSpec.shared_context "con el módulo sample sincronizado" do
  before { Access.sync!(allow_prune: true) }
end
