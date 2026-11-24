module Imports
  class EmptyFile < InvalidFile
    def initialize = super("El archivo no tiene filas de datos")
  end
end
