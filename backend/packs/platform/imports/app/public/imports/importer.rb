module Imports
  # Contract of a pack's importer, built once per batch (or chunk) for one company.
  #
  # - `COLUMNS`: CSV header (normalized: lowercase, no accents, "_") => attribute. `REQUIRED`: headers that must be there.
  # - `validate(cells)`: cells by header => [attributes, {header => error code}]. Pure: never writes, may read.
  # - `duplicate_column`: the header whose normalized value identifies a row (a repeat inside the file is rejected).
  # - `apply(attributes, mode:)`: writes one valid row and returns :created, :updated, :restored or :skipped. Raises
  #   ActiveRecord::RecordInvalid for a row the database refuses.
  class Importer
    COLUMNS = {}.freeze
    REQUIRED = [].freeze
    DUPLICATE_MODES = %w[skip].freeze

    attr_reader :company_id

    def initialize(company_id:)
      @company_id = company_id
    end

    def columns = self.class::COLUMNS
    def required_columns = self.class::REQUIRED
    def duplicate_modes = self.class::DUPLICATE_MODES

    # Codes of what the file asked for and will NOT happen, shown before confirming.
    def warnings(_headers) = []

    def duplicate_column = raise(NotImplementedError)
    def validate(_cells) = raise(NotImplementedError)
    def apply(_attributes, mode:) = raise(NotImplementedError)

    # The value whose repeat inside the file makes a row a duplicate.
    def duplicate_key(attributes) = attributes[columns.fetch(duplicate_column)]

    # The record's validation errors as {header => code}; an attribute with no column goes under "base".
    def error_codes_for(record)
      headers = columns.invert
      record.errors.details.to_h { |attribute, details| [ headers.fetch(attribute, "base"), details.first[:error].to_s ] }
    end
  end
end
