module Api
  # Reads a JSON body into well-typed values: a string where a number goes would fail deep inside the model instead of
  # answering 400.
  #
  #   def service_params = typed_params(name: String, price_minor: Integer, active: :boolean)
  #
  # Only the declared keys, and only the ones SENT in the JSON body (never the query string or the route), are returned
  # (symbolized). `nil` is accepted for String and Integer fields (it clears the value); a :boolean must be true or false.
  # An array or an object in a declared key is a type error, not a value to drop silently.
  module TypedParams
    private

    def typed_params(schema)
      # Safe to read unpermitted: every kept value is checked below to be a scalar of the declared type.
      values = ActionController::Parameters.new(request.request_parameters).slice(*schema.keys).to_unsafe_h.symbolize_keys
      invalid = values.reject { |key, value| well_typed?(schema.fetch(key), value) }.keys
      raise ActionController::BadRequest, "Tipo inválido en: #{invalid.join(', ')}" if invalid.any?

      values
    end

    def well_typed?(type, value)
      return [ true, false ].include?(value) if type == :boolean

      # A NUL byte in a string is rejected by PostgreSQL with an exception (500); it is never valid text.
      return false if value.is_a?(String) && value.include?("\u0000")

      value.nil? || value.is_a?(type)
    end
  end
end
