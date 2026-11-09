# Esquemas de eventos de prueba: se registran en el registro de Events y se retiran al terminar cada ejemplo, para no
# contaminar a los demás ni al catálogo real de packs/*/*/app/public/*/events/*.json.
module EventSchemaHelpers
  THING_HAPPENED = {
    "type" => "object",
    "required" => [ "thing_id" ],
    "properties" => { "thing_id" => { "type" => "string" }, "size" => { "type" => "integer" } },
    "additionalProperties" => false
  }.freeze

  def register_event_schema(name, schema = THING_HAPPENED)
    (@registered_event_schemas ||= []) << name
    Events::Schemas.register(name, schema)
  end

  def unregister_event_schemas
    (@registered_event_schemas || []).each { |name| Events::Schemas.unregister(name) }
  end
end

RSpec.configure do |config|
  config.include EventSchemaHelpers
  config.after { unregister_event_schemas }
end
