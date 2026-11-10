module Modules
  # Se intentó activar un módulo cuyos `requires` no están activos en la empresa.
  class RequirementsNotMet < Error
    attr_reader :key, :missing

    def initialize(key, missing)
      @key = key.to_s
      @missing = Array(missing)
      super("No se puede activar #{@key.inspect}: requiere #{@missing.join(', ')}, que no están activos en la empresa")
    end
  end
end
