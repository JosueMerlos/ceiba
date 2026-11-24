module Imports
  class FileTooLarge < InvalidFile
    attr_reader :max_bytes

    def initialize(max_bytes:)
      @max_bytes = max_bytes
      super("El archivo supera el tamaño máximo de #{max_bytes / 1.megabyte} MB")
    end
  end
end
