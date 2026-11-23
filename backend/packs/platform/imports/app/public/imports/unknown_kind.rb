module Imports
  class UnknownKind < Error
    def initialize = super("Tipo de importación desconocido: usa customers, services o professionals")
  end
end
