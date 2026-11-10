module Modules
  # A module no manifest declares was requested.
  class UnknownModule < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("No existe el módulo #{@key.inspect}")
    end
  end
end
