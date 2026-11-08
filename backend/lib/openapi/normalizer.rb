module Openapi
  # Deja un documento OpenAPI en forma canónica: claves y valores de texto (sin símbolos) y claves ordenadas en todos los niveles. Los arrays conservan su
  # orden (`parameters`, `required` y `enum` son significativos). Así `openapi/v1.yaml` no cambia por el orden en que
  # rswag fue acumulando los specs, y el check de drift no da falsos positivos.
  module Normalizer
    def self.call(node)
      case node
      when Hash then node.to_h { |key, value| [ key.to_s, call(value) ] }.sort.to_h
      when Array then node.map { |value| call(value) }
      when Symbol then node.to_s
      else node
      end
    end
  end
end
