module Modules
  # Se pidió un módulo que ningún manifiesto declara.
  class UnknownModule < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("No existe el módulo #{@key.inspect}")
    end
  end
end
