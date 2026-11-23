module Imports
  class MissingColumns < InvalidFile
    attr_reader :columns

    def initialize(columns:)
      @columns = columns
      super("Faltan columnas obligatorias: #{columns.join(', ')}")
    end
  end
end
