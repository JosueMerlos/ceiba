module Modules
  # Something that needs the module active in the company (e.g. changing its settings) was requested while it is inactive.
  class NotEnabled < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("El módulo #{@key.inspect} no está activo en la empresa")
    end
  end
end
