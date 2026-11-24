module Imports
  class UnreadableFile < InvalidFile
    def initialize = super("No se pudo leer el archivo: guárdalo como CSV desde tu hoja de cálculo")
  end
end
