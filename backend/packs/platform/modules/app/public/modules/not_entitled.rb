module Modules
  # El plan de la organización no incluye el módulo (entitlement, F6). Hoy `Modules.entitled?` siempre concede.
  class NotEntitled < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("El plan contratado no incluye el módulo #{@key.inspect}")
    end
  end
end
