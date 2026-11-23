module Imports
  # Fields match components.schemas.ImportBatch EXACTLY (the controller adds `preview`). Counts and codes only: no cell value.
  class BatchSerializer < Api::Serializer
    attributes :id, :kind, :status, :duplicate_mode, :warnings, :total_count, :ready_count, :rejected_count, :created_count,
               :updated_count, :restored_count, :skipped_count, :failed_count

    attribute(:columns) { |_batch| params[:importer].columns.keys }
    attribute(:required_columns) { |_batch| params[:importer].required_columns }
    attribute(:duplicate_modes) { |_batch| params[:importer].duplicate_modes }
    attribute(:expires_at) { |batch| batch.expires_at.utc.iso8601 }
    attribute(:confirmed_at) { |batch| batch.confirmed_at&.utc&.iso8601 }
    attribute(:finished_at) { |batch| batch.finished_at&.utc&.iso8601 }
    attribute(:created_at) { |batch| batch.created_at.utc.iso8601 }
  end
end
