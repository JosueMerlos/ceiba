module Imports
  class TooManyRows < InvalidFile
    attr_reader :rows, :max_rows

    def initialize(rows:, max_rows:)
      @rows = rows
      @max_rows = max_rows
      super("El archivo tiene #{rows} filas y el máximo es #{max_rows}: divídelo en varios archivos")
    end
  end
end
