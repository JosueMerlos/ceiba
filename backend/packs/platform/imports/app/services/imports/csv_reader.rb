require "csv"

module Imports
  # Turns the bytes of a spreadsheet export into normalized headers and rows. Spreadsheets in Spanish save CSV as
  # Windows-1252 with ";" (the decimal comma takes ","), as UTF-8 with a BOM, or as "Unicode text" (UTF-16, tabs), so the
  # encoding and the separator are detected instead of assumed.
  module CsvReader
    Result = Data.define(:headers, :rows, :encoding, :separator)
    # `number` is the row's line in the sheet (the header is 1), which is what the person sees in their spreadsheet.
    Row = Data.define(:number, :cells)

    SEPARATORS = [ ";", ",", "\t" ].freeze
    BOMS = { "UTF-8" => "\xEF\xBB\xBF".b, "UTF-16LE" => "\xFF\xFE".b, "UTF-16BE" => "\xFE\xFF".b }.freeze

    module_function

    def call(bytes, max_rows:, max_bytes:)
      raise FileTooLarge.new(max_bytes:) if bytes.bytesize > max_bytes

      text, encoding = decode(bytes.b)
      raise UnreadableFile if text.include?("\u0000")

      separator = separator_of(text)
      header, *lines = parse(text, separator)
      raise EmptyFile if header.nil?

      headers = header.map { normalize_header(it) }
      repeated = headers.compact.tally.select { |_, count| count > 1 }.keys
      raise DuplicateColumns.new(columns: repeated) if repeated.any?

      rows = lines.each_with_index.filter_map do |cells, index|
        cells = cells.map { it.to_s.strip.presence }
        Row.new(number: index + 2, cells:) if cells.any?
      end
      raise EmptyFile if rows.empty?
      raise TooManyRows.new(rows: rows.size, max_rows:) if rows.size > max_rows

      Result.new(headers:, rows:, encoding:, separator:)
    end

    # UTF-8 that is not valid is taken as Windows-1252: every byte maps to a character, so the only way to tell is validity.
    def decode(bytes)
      bom = BOMS.find { |_, mark| bytes.start_with?(mark) }
      return [ bytes.byteslice(bom.last.bytesize..).force_encoding(bom.first).encode("UTF-8"), bom.first ] if bom

      utf8 = bytes.dup.force_encoding("UTF-8")
      return [ utf8, "UTF-8" ] if utf8.valid_encoding?

      [ bytes.force_encoding("Windows-1252").encode("UTF-8"), "Windows-1252" ]
    rescue EncodingError
      raise UnreadableFile
    end

    # The separator that appears most often in the header line, ignoring what is inside quotes.
    def separator_of(text)
      header = text.each_line.first.to_s.gsub(/"[^"]*"/, "")
      SEPARATORS.max_by { |separator| [ header.count(separator), -SEPARATORS.index(separator) ] }
    end

    def parse(text, separator)
      CSV.parse(text, col_sep: separator)
    rescue CSV::MalformedCSVError
      raise UnreadableFile
    end

    def normalize_header(value)
      value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_").presence
    end
  end
end
