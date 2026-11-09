module Modules
  # Se intentó desactivar un módulo que otros módulos ACTIVOS en la empresa requieren.
  class RequiredByOthers < Error
    attr_reader :key, :dependents

    def initialize(key, dependents)
      @key = key.to_s
      @dependents = Array(dependents)
      super("No se puede desactivar #{@key.inspect}: lo requieren #{@dependents.join(', ')}, que siguen activos en la empresa")
    end
  end
end
