module Events
  # Registry of event schemas (JSON Schema). Each pack declares its own in
  # packs/<layer>/<pack>/app/public/<pack>/events/<event name>.json (e.g. `platform.organization_provisioned.v1.json`);
  # the file name IS the event name.
  #
  # `register`/`unregister` add and remove schemas in memory (for tests). An event without a schema is not published.
  module Schemas
    GLOB = "packs/*/*/app/public/*/events/*.json".freeze
    LOCK = Mutex.new

    class << self
      def names = LOCK.synchronize { registry.keys.sort }

      def register(name, schema)
        raise ArgumentError, "#{name}: el esquema no es un JSON Schema válido" unless JSONSchemer.valid_schema?(schema)

        LOCK.synchronize { registry[name.to_s] = JSONSchemer.schema(schema) }
      end

      def definition(name)
        (LOCK.synchronize { registry[name.to_s] } or raise UnknownEvent, name).value
      end

      def reload!
        LOCK.synchronize { @registry = nil }
        names
        nil
      end

      def unregister(name)
        LOCK.synchronize { registry.delete(name.to_s) }
      end

      # Returns the payload normalized to JSON (string keys); raises UnknownEvent or InvalidPayload.
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
          definition = JSON.parse(file.read)
          raise ArgumentError, "#{file.basename}: no es un JSON Schema válido" unless JSONSchemer.valid_schema?(definition)

          [ file.basename(".json").to_s, JSONSchemer.schema(definition) ]
        end
      end
    end
  end
end
