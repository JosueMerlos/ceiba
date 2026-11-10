module Modules
  # Se pidió algo que exige el módulo activo en la empresa (p. ej. cambiar sus settings) y está inactivo.
  class NotEnabled < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("El módulo #{@key.inspect} no está activo en la empresa")
    end
  end
end
