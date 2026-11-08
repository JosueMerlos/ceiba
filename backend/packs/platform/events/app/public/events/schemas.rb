module Events
  # Registro de esquemas de eventos (JSON Schema). Cada pack declara los suyos en
  # packs/<capa>/<pack>/app/public/<pack>/events/<nombre del evento>.json (p. ej.
  # `platform.organization_provisioned.v1.json`); el nombre del archivo ES el nombre del evento.
  #
  # `register`/`unregister` añaden y retiran esquemas en memoria (para pruebas). Un evento sin esquema no se publica.
  module Schemas
    GLOB = "packs/*/*/app/public/*/events/*.json".freeze
    LOCK = Mutex.new

    class << self
      def names = LOCK.synchronize { registry.keys.sort }

      def register(name, schema)
        raise ArgumentError, "#{name}: el esquema no es un JSON Schema válido" unless JSONSchemer.valid_schema?(schema)

        LOCK.synchronize { registry[name.to_s] = JSONSchemer.schema(schema) }
      end

      def unregister(name)
        LOCK.synchronize { registry.delete(name.to_s) }
      end

      # Valida el payload y lo devuelve normalizado a JSON (claves en cadena). Lanza UnknownEvent o InvalidPayload.
      def validate!(name, payload)
        schemer = LOCK.synchronize { registry[name.to_s] } or raise UnknownEvent, name
        json = payload.as_json
        violations = schemer.validate(json).map { |error| "#{error['data_pointer'].presence || '/'}: #{error['error']}" }
        raise InvalidPayload.new(name, violations) if violations.any?

        json
      end

      private

      def registry = @registry ||= load_catalog

      def load_catalog
        Rails.root.glob(GLOB).sort.to_h do |file|
          [ file.basename(".json").to_s, JSONSchemer.schema(JSON.parse(file.read)) ]
        end
      end
    end
  end
end
