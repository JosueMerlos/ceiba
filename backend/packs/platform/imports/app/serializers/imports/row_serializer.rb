module Imports
  # Fields match components.schemas.ImportRow EXACTLY. `values` (the row's cells, personal data for customers) only go out
  # while the batch is a preview, to whoever may import that kind; afterwards they are null (and erased from the row).
  class RowSerializer < Api::Serializer
    attributes :row_number, :status, :error_codes

    attribute(:values) { |row| params[:values] ? row.cells : nil }
  end
end
