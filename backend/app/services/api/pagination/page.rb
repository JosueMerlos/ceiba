module Api
  module Pagination
    # Una página ya recortada a `limit`. `meta` es el bloque `page` de la respuesta.
    Page = Data.define(:records, :next_cursor, :has_more) do
      def meta = { next_cursor:, has_more: }
    end
  end
end
