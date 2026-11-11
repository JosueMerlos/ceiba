module Modules
  # Checks the rules that apply to ONE manifest. Accumulates all problems and raises Modules::InvalidManifest with the full
  # list. Cross-manifest rules (existing `requires`, no cycles) are checked by Modules::Registry#validate!.
  class ManifestValidator
    KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
    PERMISSION_FORMAT = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/
    CONSTANT_FORMAT = /\A[A-Z]\w*(::[A-Z]\w*)*\z/
    SCOPE_FORMAT = /\A(read|write):[a-z][a-z0-9_]*\z/
    EVENT_FORMAT = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.v\d+\z/
    VERSION_FORMAT = /\A\d+\.\d+\z/
    RESERVED_KEYS = %w[platform].freeze

    # Normalized schema plus already expanded permissions and grants.
    Result = Data.define(:settings_schema, :permissions, :role_grants, :schemer)

    def self.call(declared) = new(declared).call

    def initialize(declared)
      @declared = declared
      @key = declared.key.to_s
      @problems = []
    end

    def call
      check_identity
      permissions = check_permissions
      role_grants = check_role_grants(permissions)
      check_api_scopes(permissions)
      schema, schemer = check_settings
      check_publishes
      check_navigation(permissions)
      check_hooks
      check_requires
      raise InvalidManifest.new(@key, @problems) if @problems.any?

      Result.new(settings_schema: schema, permissions:, role_grants:, schemer:)
    end

    private

    attr_reader :declared

    def problem(message) = @problems << message

    def check_identity
      problem("la key debe ser snake_case (a-z, 0-9 y _, empieza por letra)") unless KEY_FORMAT.match?(@key)
      problem("la key #{@key.inspect} está reservada para la plataforma") if RESERVED_KEYS.include?(@key)
      missing = { "name" => declared.name, "version" => declared.version }.select { |_field, value| value.to_s.strip.empty? }.keys
      problem("faltan campos obligatorios: #{missing.join(', ')}") if missing.any?
      problem("version #{declared.version.inspect} debe tener la forma \"1.0\"") if declared.version.present? && !VERSION_FORMAT.match?(declared.version.to_s)
      problem("platform debe ser una lista de capacidades") unless declared.platform.all? { |capability| capability.is_a?(Symbol) || capability.is_a?(String) }
    end

    def check_permissions
      declared.permissions.each_with_object([]) do |permission, accepted|
        key = permission[:key]
        if !PERMISSION_FORMAT.match?(key)
          problem("el permiso #{key.inspect} no sigue <modulo>.<recurso>.<accion>")
        elsif !key.start_with?("#{@key}.")
          problem("el permiso #{key.inspect} debe empezar por \"#{@key}.\" (la key del módulo)")
        elsif accepted.any? { |existing| existing.key == key }
          problem("el permiso #{key.inspect} está repetido")
        elsif permission[:description].empty?
          problem("el permiso #{key.inspect} necesita una descripción (description:)")
        elsif ![ true, false ].include?(permission[:from_descendants])
          problem("el permiso #{key.inspect}: from_descendants debe ser exactamente true o false (recibió #{permission[:from_descendants].inspect})")
        elsif permission[:from_descendants] && !Access.read_permission?(key)
          problem("el permiso #{key.inspect}: from_descendants solo se acepta en permisos de lectura (acciones #{Access::READ_ACTIONS.join(', ')})")
        else
          accepted << Manifest::Permission.new(key:, description: permission[:description], from_descendants: permission[:from_descendants])
        end
      end
    end

    def check_role_grants(permissions)
      known = permissions.map(&:key)
      declared.role_grants.to_h do |role, keys|
        problem("la concesión es a un rol que no es de sistema: #{role.inspect} (roles: #{Access::SYSTEM_ROLES.keys.join(', ')})") unless Access::SYSTEM_ROLES.key?(role)
        keys = known if keys == :all
        (keys - known).each { |key| problem("la concesión a #{role.inspect} incluye #{key.inspect}, que el módulo no declara") }
        [ role, (keys & known).freeze ]
      end
    end

    def check_api_scopes(permissions)
      known = permissions.map(&:key)
      declared.api_scopes.each do |scope, keys|
        scope = scope.to_s
        problem("el scope #{scope.inspect} debe llamarse \"read:#{@key}\" o \"write:#{@key}\"") unless SCOPE_FORMAT.match?(scope) && scope.end_with?(":#{@key}")
        Array(keys).each { |key| problem("el scope #{scope.inspect} apunta a #{key.inspect}, que el módulo no declara") unless known.include?(key.to_s) }
      end
    end

    def check_settings
      levels = declared.settings_levels.map(&:to_s)
      (levels - Manifest::LEVELS).each { |level| problem("nivel desconocido #{level.inspect} en settings_levels (niveles: #{Manifest::LEVELS.join(', ')})") }
      schema = load_schema
      return [ empty_schema, JSONSchemer.schema(empty_schema) ] if schema.nil? || !check_schema_shape(schema)

      check_properties(schema, levels)
      [ schema.merge("additionalProperties" => false), JSONSchemer.schema(schema.merge("additionalProperties" => false)) ]
    end

    def empty_schema = { "type" => "object", "properties" => {}, "additionalProperties" => false }

    def load_schema
      source = declared.settings_source
      return if source.nil?
      return stringify(source) if source.is_a?(Hash)

      path = File.expand_path(source.to_s, declared.root.to_s)
      JSON.parse(File.read(path))
    rescue Errno::ENOENT
      problem("no se pudo leer el esquema de settings #{source.inspect} (#{path})")
      nil
    rescue JSON::ParserError => error
      problem("el esquema de settings #{source.inspect} no es JSON: #{error.message.lines.first.strip}")
      nil
    end

    def stringify(hash) = JSON.parse(hash.to_json)

    def check_schema_shape(schema)
      unless JSONSchemer.valid_schema?(schema)
        problem("settings_schema no es un JSON Schema válido")
        return false
      end
      return true if schema["type"] == "object" && schema["properties"].is_a?(Hash)

      problem("el esquema de settings debe ser type: object con properties")
      false
    end

    def check_properties(schema, levels)
      schema["properties"].each do |name, property|
        unless property.is_a?(Hash) && property.key?("default")
          problem("la propiedad #{name.inspect} de settings no tiene default (toda propiedad lo necesita)")
          next
        end
        problem("la propiedad #{name.inspect} tiene un default que no cumple su propio esquema") unless JSONSchemer.schema(property).valid?(property["default"])
        check_auditable_name(name)
        check_bounds(property, name)
        Array(property["x-levels"]).each do |level|
          problem("la propiedad #{name.inspect} usa x-levels #{level.inspect}, que no está en settings_levels (#{levels.join(', ')})") unless levels.include?(level)
        end
      end
    end

    # BOUNDS: settings travel in every /me and live in jsonb; unbounded, a giant value (50,000 reminders, 10**30) bloats or breaks
    # them. Every array needs maxItems, every free string (not enum/const) maxLength and every number minimum and maximum,
    # also inside objects and array items (`a[].n`).
    def check_bounds(node, path)
      return unless node.is_a?(Hash)

      types = Array(node["type"])
      problem("la propiedad #{path.inspect} (array) necesita maxItems") if types.include?("array") && !node.key?("maxItems")
      if types.include?("string") && !node.key?("maxLength") && !node.key?("enum") && !node.key?("const")
        problem("la propiedad #{path.inspect} (string) necesita maxLength (o ser un enum)")
      end
      if (types & %w[integer number]).any? && !(bounded?(node, "minimum", "exclusiveMinimum") && bounded?(node, "maximum", "exclusiveMaximum"))
        problem("la propiedad #{path.inspect} (#{(types & %w[integer number]).first}) necesita minimum y maximum")
      end
      check_bounds(node["items"], "#{path}[]")
      node["properties"]&.each { |name, child| check_bounds(child, "#{path}.#{name}") }
    end

    def bounded?(node, *keywords) = keywords.any? { |keyword| node.key?(keyword) } || node.key?("enum") || node.key?("const")

    # The settings audit stores the diff with the same masking as logs (filter_parameters plus digest/csrf/ciphertext), so a
    # sensitive-named property would lose its value in the audit: settings are no place for secrets.
    def check_auditable_name(name)
      return unless self.class.sensitive_name?(name)

      problem("el nombre de la propiedad #{name.inspect} coincide con filter_parameters: la auditor\u00eda enmascarar\u00eda su valor. Ren\u00f3mbrala (los secretos no van en settings)")
    end

    def self.sensitive_name?(name)
      filters = Rails.application.config.filter_parameters + [ /digest/i, /csrf/i, /ciphertext/i ]
      ActiveSupport::ParameterFilter.new(filters).filter(name.to_s => 1)[name.to_s] != 1
    end

    def check_publishes
      known = Events::Schemas.names
      declared.publishes.each do |event|
        problem("el evento publicado #{event.inspect} no tiene esquema registrado (app/public/<pack>/events/#{event}.json)") unless known.include?(event.to_s)
      end
      declared.subscribes.each_key do |event|
        problem("la suscripción a #{event.inspect} no es un nombre de evento válido") unless EVENT_FORMAT.match?(event.to_s)
      end
    end

    def check_navigation(permissions)
      known = permissions.map(&:key)
      keys = []
      declared.navigation.each do |item|
        item = item.to_h.symbolize_keys
        label = (item[:key] || "?").inspect
        problem("la navegación #{label} necesita key") if item[:key].blank?
        problem("la navegación #{label} necesita path (que empiece por \"/\")") unless item[:path].to_s.start_with?("/")
        problem("la navegación #{label} usa el permiso #{item[:permission].inspect}, que el módulo no declara") unless known.include?(item[:permission].to_s)
        problem("la navegación #{label} está repetida") if keys.include?(item[:key])
        keys << item[:key]
      end
    end

    def check_hooks
      { on_enable: declared.on_enable, on_disable: declared.on_disable }.each do |hook, constant_name|
        next if constant_name.nil? || CONSTANT_FORMAT.match?(constant_name.to_s)

        problem("#{hook} debe ser el nombre de una constante (#{constant_name.to_s.inspect})")
      end
    end

    def check_requires
      problem("un módulo no puede requerirse a sí mismo") if declared.requires.map(&:to_s).include?(@key)
    end
  end
end
