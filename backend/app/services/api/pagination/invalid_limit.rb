module Api
  module Pagination
    # `limit` is not an integer between 1 and Cursor::MAX_LIMIT.
    class InvalidLimit < Error; end
  end
end
