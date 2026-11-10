module Modules
  # Los settings no cumplen el esquema del módulo (o piden una clave que no existe o no se permite en ese nivel). `errors` es el
  # detalle POR CAMPO: [{ field:, code:, message: }]; la API lo devuelve como 422 (modules.invalid_settings).
  class InvalidSettings < Error
    attr_reader :key, :errors

    def initialize(key, errors)
      @key = key.to_s
      @errors = Array(errors).freeze
      super("Settings inválidos para #{@key.inspect}: #{@errors.map { |error| "#{error[:field]} #{error[:message]}" }.join('; ')}")
    end
  end
end
