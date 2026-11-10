require "rswag/specs"
require "rswag/specs/swagger_formatter"
require "openapi/normalizer"

module Openapi
  # rswag formatter that writes the document in canonical form (sorted keys). Used by `bin/rails openapi:generate`, not
  # invoked by hand.
  class Formatter < Rswag::Specs::SwaggerFormatter
    # RSpec registers formatters by class: the subclass does not inherit its parent's registration.
    ::RSpec::Core::Formatters.register self, :example_group_finished, :stop

    private

    # rswag declares `produces` per OPERATION and copies it to all its responses: a 200 would also come out as
    # problem+json and a 404 as json, and the generated client would get absurd unions. A success response is
    # application/json; an error one (>= 400), application/problem+json.
    def prune_content_types(doc)
      doc = doc.deep_dup
      doc[:paths]&.each_value do |path_item|
        path_item.each_value do |operation|
          next unless operation.is_a?(Hash)

          operation[:responses]&.each do |code, response|
            kept = code.to_s.to_i >= 400 ? "application/problem+json" : "application/json"
            # No select!: rswag shares the same `content` Hash across an operation's responses.
            response[:content] = response[:content].select { |media_type, _| media_type == kept } if response[:content]
          end
        end
      end
      doc
    end

    # No line wrapping (line_width -1): Psych's folding of long text is a version detail that must not decide whether
    # there is drift.
    def pretty_generate(doc)
      normalized = Normalizer.call(prune_content_types(doc))
      @config.openapi_format == :yaml ? YAML.dump(normalized, line_width: -1) : JSON.pretty_generate(normalized)
    end
  end
end
