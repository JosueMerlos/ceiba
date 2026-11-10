module Modules
  # El registro de manifiestos (docs/architecture/05-module-system.md). `Modules.registry` es el global de la aplicación;
  # los specs construyen los suyos con `Modules::Registry.new`.
  #
  #   registry.define(:loyalty) { name "Lealtad"; version "1.0"; ... }   # valida el manifiesto al definirlo
  #   registry.validate!                                                   # reglas entre manifiestos (requires)
  class Registry
    def initialize
      @manifests = {}
      @lock = Mutex.new
    end

    # Declara un módulo. `root` es el directorio de su pack (de él cuelga la ruta relativa de `settings_schema`). Valida
    # el manifiesto entero: si algo está mal lanza Modules::InvalidManifest con todos los problemas.
    def define(key, root: nil, &block)
      key = key.to_s
      declared = ManifestBuilder.build(key, root:, &block)
      validated = ManifestValidator.call(declared)
      manifest = build_manifest(declared, validated)
      @lock.synchronize do
        raise InvalidManifest.new(key, [ "el módulo ya está definido" ]) if @manifests.key?(key)

        clash = clashing_permission(manifest)
        raise InvalidManifest.new(key, [ "el permiso #{clash.last.inspect} ya lo declara el módulo #{clash.first.inspect}" ]) if clash

        @manifests[key] = manifest
      end
    end

    def fetch(key) = @manifests.fetch(key.to_s) { raise UnknownModule, key }
    def key?(key) = @manifests.key?(key.to_s)
    def keys = @manifests.keys
    def all = @manifests.values
    def each(&) = all.each(&)

    # Módulos que dicen requerir a `key` (los que dejarían de funcionar si se desactiva).
    def requirers_of(key) = all.select { |manifest| manifest.requires.include?(key.to_s) }

    # Reglas ENTRE manifiestos: `requires` apunta a módulos que existen y no forma ciclos. Se llama una vez cargados todos.
    def validate!
      all.each do |manifest|
        missing = manifest.requires - keys
        raise InvalidManifest.new(manifest.key, [ "requires referencia módulos que no existen: #{missing.map(&:inspect).join(', ')}" ]) if missing.any?
      end
      cycle = find_cycle
      raise InvalidManifest.new(cycle.first, [ "requires forma un ciclo: #{cycle.join(' -> ')}" ]) if cycle

      self
    end

    private

    def build_manifest(declared, validated)
      Manifest.new(
        key: declared.key, name: declared.name.to_s, version: declared.version.to_s, requires: declared.requires.map(&:to_s).freeze,
        platform: declared.platform.map(&:to_s).freeze, permissions: validated.permissions.freeze, role_grants: validated.role_grants.freeze,
        api_scopes: declared.api_scopes.to_h { |scope, keys| [ scope.to_s, Array(keys).map(&:to_s).freeze ] }.freeze,
        settings_schema: deep_freeze(validated.settings_schema), settings_levels: declared.settings_levels.map(&:to_s).freeze,
        publishes: declared.publishes.map(&:to_s).freeze, subscribes: declared.subscribes.to_h { |event, subscriber| [ event.to_s, subscriber.to_s ] }.freeze,
        navigation: declared.navigation.map { |item| item.to_h.symbolize_keys.slice(:key, :path, :permission).freeze }.freeze,
        on_enable: declared.on_enable&.to_s, on_disable: declared.on_disable&.to_s, schemer: validated.schemer
      )
    end

    def clashing_permission(manifest)
      @manifests.each_value do |other|
        shared = other.permission_keys & manifest.permission_keys
        return [ other.key, shared.first ] if shared.any?
      end
      nil
    end

    # Primer ciclo de `requires` como lista de keys (la primera repetida al final), o nil.
    def find_cycle
      done = Set.new
      keys.each do |key|
        cycle = cycle_from(key, [], done)
        return cycle if cycle
      end
      nil
    end

    def cycle_from(key, path, done)
      return if done.include?(key)
      return path[path.index(key)..] + [ key ] if path.include?(key)

      @manifests.fetch(key).requires.each do |required|
        cycle = cycle_from(required, path + [ key ], done)
        return cycle if cycle
      end
      done << key
      nil
    end

    def deep_freeze(value)
      case value
      when Hash then value.each { |key, item| deep_freeze(key) && deep_freeze(item) }
      when Array then value.each { |item| deep_freeze(item) }
      end
      value.freeze
    end
  end
end
