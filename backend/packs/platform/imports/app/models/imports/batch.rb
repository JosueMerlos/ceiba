module Imports
  # One uploaded CSV, from its preview to its final report. TENANT table scoped to the company it was uploaded for and the
  # branch it was uploaded from (only ids, no association to the private Tenancy models). Counts and codes only: the
  # cells live, encrypted and short-lived, in its rows.
  class Batch < ApplicationRecord
    self.table_name = "import_batches"

    KINDS = %w[customers services professionals].freeze
    STATUSES = %w[previewed queued processing completed failed expired].freeze
    RUNNING = %w[queued processing].freeze
    DUPLICATE_MODES = %w[skip update].freeze
    # One counter per row status: a new row outcome is counted without touching this list.
    COUNTERS = Row::STATUSES
    # An unconfirmed preview keeps personal data at rest: it expires a day after the upload.
    PREVIEW_TTL = 24.hours

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    has_many :rows, -> { order(:row_number) }, class_name: "Imports::Row", foreign_key: :import_batch_id, inverse_of: :batch, dependent: nil

    validates :company_id, :branch_id, :created_by_id, :expires_at, presence: true
    validates :kind, inclusion: { in: KINDS }
    validates :status, inclusion: { in: STATUSES }
    validates :duplicate_mode, inclusion: { in: DUPLICATE_MODES }, allow_nil: true

    # The importer of this batch's kind, for its company.
    def importer = Registry.fetch(kind).importer_for(company_id:)

    def previewed? = status == "previewed"
    def running? = RUNNING.include?(status)
    def confirmable?(now: Time.current) = previewed? && expires_at > now

    # Recomputes every counter from the rows themselves, so a retried chunk can never count a row twice.
    def refresh_counts! = update!(counts_from_rows)

    def counts_from_rows
      tally = rows.unscope(:order).group(:status).count
      { total_count: tally.values.sum, **COUNTERS.to_h { [ :"#{it}_count", tally.fetch(it, 0) ] } }
    end
  end
end
