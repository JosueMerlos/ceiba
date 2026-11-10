module Audit
  # Attribute diff for audit_events (privacy of the audit trail).
  #
  #   Audit::Diff.call(before: { "name" => "A" }, after: { "name" => "B" }, encrypted_attributes: [:phone])
  #   # => { before: { "name" => "A" }, after: { "name" => "B" } }
  #
  # - With both sides, keeps only top-level keys whose value changed (or appeared/disappeared). A create (before nil) or
  #   a delete (after nil) keeps the whole present side.
  # - SENSITIVE keys are masked as "[FILTERED]" with the SAME criteria as the logs (`config.filter_parameters`) plus
  #   digest, csrf and ciphertext, RECURSIVELY (nested hashes and arrays: a jsonb `settings: { whatsapp_token: … }` does
  #   not slip through). The key is kept: that a password changed is auditable, its value is not. Matching is by NAME
  #   substring, so it over-masks (`footprint` contains `otp`) and never under-masks.
  # - ENCRYPTED PII (attributes the subject declares with `encrypts`): compared by real value to detect a change, but
  #   stored as "[FILTERED]". An unchanged encrypted value does not appear.
  class Diff
    FILTERED = ActiveSupport::ParameterFilter::FILTERED
    EXTRA_FILTERS = [ /digest/i, /csrf/i, /ciphertext/i ].freeze

    def self.call(...) = new(...).call

    def initialize(before:, after:, encrypted_attributes: [])
      @before = stringify(before)
      @after = stringify(after)
      @encrypted = Array(encrypted_attributes).map(&:to_s)
    end

    def call
      keys = changed_keys
      { before: render(@before, keys), after: render(@after, keys) }
    end

    private

    # Read on each call: another initializer may extend filter_parameters after this file loads.
    def parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + EXTRA_FILTERS)

    def changed_keys
      return (@before || @after || {}).keys if @before.nil? || @after.nil?

      (@before.keys | @after.keys).reject { |key| @before.fetch(key, nil) == @after.fetch(key, nil) && @before.key?(key) == @after.key?(key) }
    end

    def render(side, keys)
      return if side.nil?

      parameter_filter.filter(side.slice(*keys)).to_h { |key, value| [ key, @encrypted.include?(key) ? FILTERED : value ] }
    end

    def stringify(value)
      case value
      when Hash then value.to_h { |key, nested| [ key.to_s, stringify(nested) ] }
      when Array then value.map { |nested| stringify(nested) }
      else value
      end
    end
  end
end
