module Imports
  # Applies the next chunk of a confirmed batch. Runs as an event subscriber, inside the batch's tenant context and ONE
  # transaction: a chunk is all or nothing, so each delivery handles a bounded number of rows and, if rows remain, asks for
  # the next chunk in that same transaction. Progress is visible between chunks and a crash loses at most one chunk.
  #
  # Idempotent: only `ready` rows are applied and each one leaves that state when applied, and counters are recomputed
  # from the rows. A row the database refuses ends `failed` with its error codes, never the whole batch.
  module ProcessChunk
    EVENT = "platform.import_chunk_requested.v1".freeze
    CHUNK_SIZE = 200

    module_function

    def request(batch) = Events.publish(EVENT, import_batch_id: batch.id)

    def call(batch_id:)
      batch = Batch.lock.find_by(id: batch_id)
      return unless batch&.running?

      batch.update!(status: "processing") if batch.status == "queued"
      importer = batch.importer
      as_user(batch) do
        batch.rows.where(status: "ready").limit(CHUNK_SIZE).each { apply(it, importer, batch.duplicate_mode) }
        next finish(batch) unless batch.rows.exists?(status: "ready")

        request(batch)
        batch.refresh_counts!
      end
    end

    # A row that no longer validates (the data changed since the preview) or that the database refuses ends `failed`.
    def apply(row, importer, mode)
      attributes, errors = importer.validate(row.cells)
      return mark_failed(row, errors) if errors.any?

      outcome = ApplicationRecord.transaction(requires_new: true) { importer.apply(attributes, mode:) }
      row.update!(status: outcome.to_s, payload: nil)
    rescue ActiveRecord::RecordInvalid => error
      mark_failed(row, importer.error_codes_for(error.record))
    end

    def mark_failed(row, codes) = row.update!(status: "failed", payload: nil, error_codes: codes.presence || { "base" => "invalid" })

    def finish(batch)
      batch.rows.unscope(:order).where.not(payload: nil).update_all(payload: nil)
      batch.update!(status: "completed", finished_at: Time.current)
      batch.refresh_counts!
      Audit.record(action: "import.completed", subject: batch, metadata: batch.slice(:kind, *Batch::COUNTERS.map { "#{it}_count" }))
    end

    def as_user(batch, &)
      Tenancy.with_context(organization: Current.context.organization, principal: Actor.new(id: batch.created_by_id), &)
    end
  end
end
