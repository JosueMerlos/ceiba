module Api
  # Convierte errores de validación en `errors[]` del problema: { field, code, message } por cada uno.
  module FieldErrors
    # `code` es el tipo del error de Active Model (:blank, :taken...) y es estable para el frontend; si el error
    # lleva un mensaje propio en lugar de un tipo, el código es "invalid".
    def self.from_record(record)
      record.errors.map do |error|
        { field: error.attribute.to_s, code: error.type.is_a?(Symbol) ? error.type.to_s : "invalid", message: error.message }
      end
    end
  end
end
