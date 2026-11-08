require "rswag/specs"
require "rswag/specs/swagger_formatter"
require "openapi/normalizer"

module Openapi
  # Formateador de rswag que escribe el documento en forma canónica (claves ordenadas). Se usa con
  # `bin/rails openapi:generate`, no se invoca a mano.
  class Formatter < Rswag::Specs::SwaggerFormatter
    # RSpec registra los formateadores por clase: la subclase no hereda el registro de la madre.
    ::RSpec::Core::Formatters.register self, :example_group_finished, :stop

    private

    # Sin ajuste de línea (line_width -1): el plegado de textos largos de Psych es un detalle de versión que no debe
    # decidir si hay drift.
    def pretty_generate(doc)
      normalized = Normalizer.call(doc)
      @config.openapi_format == :yaml ? YAML.dump(normalized, line_width: -1) : JSON.pretty_generate(normalized)
    end
  end
end
