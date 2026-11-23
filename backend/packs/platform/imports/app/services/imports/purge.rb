module Imports
  # Retention of import data:
  # - a preview nobody confirmed expires a day after the upload: its rows (and their cells) are deleted;
  # - a batch still running a day after its confirmation is stuck (its chunk events died): it ends `failed` and the cells
  #   of the rows it did not apply are erased.
  # Batches and their counts stay: they hold no personal data.
  #
  # Finding WHICH organizations have something due is the only cross-tenant step, and it only reads; each organization is
  # then purged by a tenant job, inside its own context, like any other write.
  module Purge
    STUCK_AFTER = 24.hours
    BATCH_SIZE = 1_000

    module_function

    def due_organization_ids(now: Time.current)
      CrossTenant.run { due(now).distinct.pluck(:organization_id) }
    end

    # Must run inside the organization's tenant context.
    def call(now: Time.current)
      due(now).find_each { it.previewed? ? expire(it) : fail_stuck(it, now) }
    end

    def due(now)
      Batch.where(status: "previewed", expires_at: ...now).or(Batch.where(status: Batch::RUNNING, confirmed_at: ...(now - STUCK_AFTER)))
    end

    def expire(batch)
      loop { break if Row.where(id: batch.rows.unscope(:order).limit(BATCH_SIZE).select(:id)).delete_all < BATCH_SIZE }
      batch.update!(status: "expired", **batch.counts_from_rows)
    end

    def fail_stuck(batch, now)
      ApplicationRecord.transaction(requires_new: true) do
        batch.rows.unscope(:order).where(status: "ready").update_all(status: "failed", error_codes: { "base" => "timeout" }, updated_at: now)
        batch.rows.unscope(:order).where.not(payload: nil).update_all(payload: nil, updated_at: now)
        batch.update!(status: "failed", finished_at: now, **batch.counts_from_rows)
      end
    end
  end
end
