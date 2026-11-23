module Imports
  # Reads an uploaded CSV and stores it as a batch awaiting confirmation: every row validated by the kind's importer, none
  # applied. A file that cannot become a batch (too big, too many rows, unreadable, missing columns) raises InvalidFile and
  # leaves nothing behind.
  module CreateBatch
    MAX_ROWS = 5_000
    MAX_BYTES = 5.megabytes
    INSERT_SLICE = 1_000

    module_function

    def call(kind:, bytes:, company_id:, branch_id:, created_by_id:)
      importer = Registry.fetch(kind).importer_for(company_id:)
      file = CsvReader.call(bytes, max_rows: MAX_ROWS, max_bytes: MAX_BYTES)
      missing = importer.required_columns - file.headers
      raise MissingColumns.new(columns: missing) if missing.any?

      rows = validate(importer, file)
      ApplicationRecord.transaction(requires_new: true) do
        batch = Batch.create!(kind:, company_id:, branch_id:, created_by_id:, warnings: importer.warnings(file.headers), expires_at: Batch::PREVIEW_TTL.from_now)
        insert_rows(batch, rows)
        batch.tap(&:refresh_counts!)
      end
    end

    def validate(importer, file)
      seen = Set.new
      file.rows.map do |row|
        cells = file.headers.zip(row.cells).to_h.slice(*importer.columns.keys)
        attributes, errors = importer.validate(cells)
        if errors.empty?
          key = importer.duplicate_key(attributes)
          errors = { importer.duplicate_column => "duplicate_in_file" } unless seen.add?(key)
        end
        { row_number: row.number, status: errors.empty? ? "ready" : "rejected", payload: cells.to_json, error_codes: errors }
      end
    end

    # One INSERT per slice instead of one per row: row by row, 5000 rows took over 8 s inside the request. organization_id is
    # explicit so the tenant write guard checks every row against the active tenant; insert_all! still encrypts the payload.
    def insert_rows(batch, rows)
      now = Time.current
      rows.each_slice(INSERT_SLICE) do |slice|
        Row.insert_all!(slice.map { it.merge(organization_id: batch.organization_id, import_batch_id: batch.id, created_at: now, updated_at: now) })
      end
    end
  end
end
