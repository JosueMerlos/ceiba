module Api
  # Converts validation errors into the problem's `errors[]`: { field, code, message } for each one.
  module FieldErrors
    # `code` is the Active Model error type (:blank, :taken...), stable for the frontend; if the error carries a custom
    # message instead of a type, the code is "invalid".
    def self.from_record(record)
      record.errors.map do |error|
        { field: error.attribute.to_s, code: error.type.is_a?(Symbol) ? error.type.to_s : "invalid", message: error.message }
      end
    end
  end
end
