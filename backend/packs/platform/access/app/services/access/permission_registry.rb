module Access
  # Registro en memoria de los permisos declarados por los packs. Una instancia global vive en `Access.registry` (se
  # reconstruye en cada recarga de código y los packs vuelven a declarar desde `config.to_prepare`).
  class PermissionRegistry
    Definition = Data.define(:key, :module_key, :description, :roles, :from_descendants)

    MODULE_KEY = /\A[a-z][a-z0-9_]*\z/
    OPTIONS = %i[description roles from_descendants].freeze
    # Acciones de LECTURA: las únicas a las que se aplica `from_descendants` (la lectura ascendente nunca concede escribir).
    READ_ACTIONS = %w[read list show view].freeze

    def initialize
      @definitions = {}
      @lock = Mutex.new
    end

    # Reemplaza TODO lo que `module_key` había declarado (volver a registrar el módulo es idempotente y retira lo que ya no
    # declara). Valida todo antes de tocar el registro: una declaración inválida no deja nada a medias.
    def register(module_key, permissions)
      module_key = module_key.to_s
      raise ArgumentError, "módulo inválido: #{module_key.inspect}" unless MODULE_KEY.match?(module_key)
      raise ArgumentError, "los permisos deben ser un Hash clave => { description:, roles: }" unless permissions.respond_to?(:to_h)

      definitions = permissions.to_h.map { |key, options| build(module_key, key.to_s, options) }
      @lock.synchronize do
        taken = definitions.find { |definition| @definitions[definition.key] && @definitions[definition.key].module_key != module_key }
        raise ArgumentError, "el permiso #{taken.key} ya lo declaró el módulo #{@definitions[taken.key].module_key}" if taken

        @definitions = @definitions.reject { |_key, existing| existing.module_key == module_key }
          .merge(definitions.index_by(&:key))
      end
    end

    def fetch(key) = @definitions.fetch(key)
    def keys = @definitions.keys
    def registered?(key) = @definitions.key?(key)
    def definitions = @definitions.values

    # Permisos de LECTURA que un membership de sucursal ejerce también sobre la empresa de esa sucursal (nunca sobre sus hermanas).
    def upward_keys = @definitions.values.select(&:from_descendants).map(&:key)

    private

    def build(module_key, key, options)
      unknown = options.keys.map(&:to_sym) - OPTIONS
      raise ArgumentError, "opciones desconocidas para #{key}: #{unknown.join(', ')}" if unknown.any?
      raise ArgumentError, "#{key} no sigue <modulo>.<recurso>.<accion>" unless Permission::KEY_FORMAT.match?(key)
      raise ArgumentError, "#{key} debe empezar por el módulo que lo declara (#{module_key})" unless key.start_with?("#{module_key}.")

      if options[:from_descendants] && !READ_ACTIONS.include?(key.split(".").last)
        raise ArgumentError, "#{key}: from_descendants solo se acepta en permisos de lectura (acciones #{READ_ACTIONS.join(', ')})"
      end

      description = options[:description].to_s.strip
      raise ArgumentError, "#{key} necesita una descripción" if description.empty?

      roles = Array(options[:roles]).map(&:to_s)
      unknown_roles = roles - SYSTEM_ROLES.keys
      raise ArgumentError, "#{key} concede a roles que no son de sistema: #{unknown_roles.join(', ')}" if unknown_roles.any?

      Definition.new(key:, module_key:, description:, roles: roles.uniq.freeze, from_descendants: options[:from_descendants] == true)
    end
  end
end
