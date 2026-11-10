module Api
  module Pagination
    # The cursor is not one this API issued: tampered, made up, for another purpose or with unexpected content.
    class InvalidCursor < Error; end
  end
end
