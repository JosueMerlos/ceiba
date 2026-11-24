module Imports
  # One data row of a batch. `payload` is the JSON of its cells (personal data for customers), encrypted and erased once the
  # row is processed or the batch expires. `error_codes` is {column => code}: the report never needs the value.
  class Row < ApplicationRecord
    self.table_name = "import_rows"

    STATUSES = %w[ready rejected created updated restored skipped failed].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    belongs_to :batch, class_name: "Imports::Batch", foreign_key: :import_batch_id, inverse_of: :rows

    encrypts :payload

    validates :row_number, numericality: { only_integer: true, greater_than: 0 }
    validates :status, inclusion: { in: STATUSES }

    def cells = payload ? JSON.parse(payload) : {}
  end
end
