module Imports
  class DuplicateModeNotAllowed < Error
    attr_reader :allowed

    def initialize(allowed:)
      @allowed = allowed
      super("Modo de duplicados no admitido para este tipo: usa #{allowed.join(' o ')}")
    end
  end
end
