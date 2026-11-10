require "rails_helper"

RSpec.describe Modules::SettingsValidator do
  let(:manifest) do
    Modules::Registry.new.define(:anidado) do
      name "Anidado"
      version "1.0"
      settings_schema(
        type: "object",
        properties: {
          reminders: {
            type: "array", maxItems: 5, default: [],
            items: { type: "object", required: %w[kind offset_minutes],
                     properties: { kind: { type: "string", maxLength: 10 }, offset_minutes: { type: "integer", minimum: 1, maximum: 9999 } } }
          }
        }
      )
    end
  end

  it "reporta los campos anidados con su ruta (por posición y clave)" do
    errors = described_class.call(manifest, { "reminders" => [ { "kind" => "2h", "offset_minutes" => 0 }, { "kind" => "1h" } ] })

    expect(errors.pluck(:field)).to contain_exactly("reminders.0.offset_minutes", "reminders.1.offset_minutes")
  end

  it "distingue el código: minimum, required y type" do
    errors = described_class.call(manifest, { "reminders" => [ { "kind" => 5, "offset_minutes" => 0 }, { "kind" => "1h" } ] })

    expect(errors.pluck(:code)).to contain_exactly("type", "minimum", "required")
  end

  it "un objeto válido no da errores" do
    expect(described_class.call(manifest, { "reminders" => [ { "kind" => "2h", "offset_minutes" => 120 } ] })).to be_empty
  end

  it "una propiedad que el esquema no define es `unknown`" do
    expect(described_class.call(manifest, { "otra" => 1 })).to eq([ { field: "otra", code: "unknown", message: "no es un ajuste de este módulo" } ])
  end
end
