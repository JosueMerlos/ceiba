module Modules
  # Tried to enable a module whose `requires` are not active in the company.
  class RequirementsNotMet < Error
    attr_reader :key, :missing

    def initialize(key, missing)
      @key = key.to_s
      @missing = Array(missing)
      super("No se puede activar #{@key.inspect}: requiere #{@missing.join(', ')}, que no están activos en la empresa")
    end
  end
end
