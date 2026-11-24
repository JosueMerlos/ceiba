module Imports
  class DuplicateColumns < InvalidFile
    attr_reader :columns

    def initialize(columns:)
      @columns = columns
      super("Hay columnas repetidas: #{columns.join(', ')}")
    end
  end
end
