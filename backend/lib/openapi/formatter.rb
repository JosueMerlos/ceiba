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

    # rswag declara `produces` por OPERACIÓN y lo copia a todas sus respuestas: un 200 saldría también como
    # problem+json y un 404 como json, y el cliente generado tendría uniones absurdas. Una respuesta de éxito es
    # application/json; una de error (>= 400), application/problem+json.
    def prune_content_types(doc)
      doc = doc.deep_dup
      doc[:paths]&.each_value do |path_item|
        path_item.each_value do |operation|
          next unless operation.is_a?(Hash)

          operation[:responses]&.each do |code, response|
            kept = code.to_s.to_i >= 400 ? "application/problem+json" : "application/json"
            # Sin select!: rswag comparte el mismo Hash `content` entre las respuestas de una operación.
            response[:content] = response[:content].select { |media_type, _| media_type == kept } if response[:content]
          end
        end
      end
      doc
    end

    # Sin ajuste de línea (line_width -1): el plegado de textos largos de Psych es un detalle de versión que no debe
    # decidir si hay drift.
    def pretty_generate(doc)
      normalized = Normalizer.call(prune_content_types(doc))
      @config.openapi_format == :yaml ? YAML.dump(normalized, line_width: -1) : JSON.pretty_generate(normalized)
    end
  end
end
