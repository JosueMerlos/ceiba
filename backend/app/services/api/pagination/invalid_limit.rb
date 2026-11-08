module Api
  module Pagination
    # `limit` no es un entero entre 1 y Cursor::MAX_LIMIT.
    class InvalidLimit < Error; end
  end
end
