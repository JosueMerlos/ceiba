module Api
  module Pagination
    # El cursor no es uno que emitió esta API: manipulado, inventado, de otro propósito o con contenido inesperado.
    class InvalidCursor < Error; end
  end
end
