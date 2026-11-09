# Payload mínimo válido de un esquema de evento (solo propiedades requeridas, por tipo y formato). Lo usa la suite de
# eventos de plataforma para comprobar que cada esquema del catálogo es satisfacible.
module EventSamples
  module_function

  def payload_for(schema)
    (schema["required"] || []).to_h { |key| [ key, value_for(schema.dig("properties", key) || {}) ] }
  end

  def value_for(property)
    return property["enum"].first if property["enum"]

    case property["type"]
    when "string" then string_for(property)
    when "integer" then property["minimum"] || 1
    when "number" then property["minimum"] || 1.5
    when "boolean" then true
    when "array" then []
    when "object" then payload_for(property)
    end
  end

  def string_for(property)
    case property["format"]
    when "uuid" then SecureRandom.uuid
    when "date-time" then Time.current.iso8601
    when "date" then Date.current.iso8601
    else "x" * [ property["minLength"] || 1, 1 ].max
    end
  end
end
