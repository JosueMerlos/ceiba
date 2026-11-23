module Imports
  # Retention of import data:
  # - a preview nobody confirmed expires a day after the upload: its rows (and their cells) are deleted;
  # - a batch still running a day after its confirmation is stuck (its chunk events died): it ends `failed` and the cells
  #   of the rows it did not apply are erased.
  # Batches and their counts stay: they hold no personal data.
  #
  # Finding WHICH batches are due is the only cross-tenant step, and it only reads. Each batch is then purged by its own
  # tenant job, in its own transaction, so one batch that fails never holds back the others' personal data.
  module Purge
    STUCK_AFTER = 24.hours

    module_function

    # [organization_id, batch_id] of every batch due, across organizations.
    def due(now: Time.current)
      CrossTenant.run { due_scope(now).pluck(:organization_id, :id) }
    end

    # Must run inside the batch's tenant context. The batch is locked and its state read again: it may have been
    # confirmed, or finished, since it was listed.
    def call(batch_id:, now: Time.current)
      batch = Batch.lock.find_by(id: batch_id)
      return unless batch && due_scope(now).exists?(id: batch.id)

      batch.previewed? ? expire(batch) : fail_stuck(batch, now)
    end

    def due_scope(now)
      Batch.where(status: "previewed", expires_at: ...now).or(Batch.where(status: Batch::RUNNING, confirmed_at: ...(now - STUCK_AFTER)))
    end

    def expire(batch)
      batch.rows.unscope(:order).delete_all
      batch.update!(status: "expired")
    end

    def fail_stuck(batch, now)
      batch.rows.unscope(:order).where(status: "ready").update_all(status: "failed", error_codes: { "base" => "timeout" }, updated_at: now)
      batch.rows.unscope(:order).where.not(payload: nil).update_all(payload: nil, updated_at: now)
      batch.update!(status: "failed", finished_at: now, **batch.counts_from_rows)
    end
  end
end
