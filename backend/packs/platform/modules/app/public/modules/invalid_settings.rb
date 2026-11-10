module Modules
  # Settings violate the module's schema (or name a key that does not exist or is not allowed at that level). `errors` is the
  # per-field detail [{ field:, code:, message: }]; the API returns it as 422 (modules.invalid_settings).
  class InvalidSettings < Error
    attr_reader :key, :errors

    def initialize(key, errors)
      @key = key.to_s
      @errors = Array(errors).freeze
      super("Settings inválidos para #{@key.inspect}: #{@errors.map { |error| "#{error[:field]} #{error[:message]}" }.join('; ')}")
    end
  end
end
