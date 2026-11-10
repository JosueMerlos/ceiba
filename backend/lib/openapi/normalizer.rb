module Openapi
  # Puts an OpenAPI document in canonical form: text keys and values (no symbols) and sorted keys at every level.
  # Arrays keep their order (`parameters`, `required` and `enum` are significant). So `openapi/v1.yaml` does not change
  # with the order rswag accumulated the specs in, and the drift check has no false positives.
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
