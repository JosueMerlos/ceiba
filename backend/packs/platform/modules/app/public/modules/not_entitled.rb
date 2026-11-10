module Modules
  # The organization's plan does not include the module. `Modules.entitled?` always grants for now.
  class NotEntitled < Error
    attr_reader :key

    def initialize(key)
      @key = key.to_s
      super("El plan contratado no incluye el módulo #{@key.inspect}")
    end
  end
end
