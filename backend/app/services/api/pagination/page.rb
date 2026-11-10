module Api
  module Pagination
    # A page already trimmed to `limit`. `meta` is the response's `page` block.
    Page = Data.define(:records, :next_cursor, :has_more) do
      def meta = { next_cursor:, has_more: }
    end
  end
end
