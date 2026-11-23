module Imports
  # Confirms a previewed batch: records the duplicate mode, queues it and publishes the request for its first chunk in the
  # same transaction (the outbox delivers it after the commit). One batch per kind runs at a time in a company; the
  # partial unique index on running batches is what guarantees it under concurrency.
  module ConfirmBatch
    module_function

    def call(batch:, duplicate_mode:)
      batch.lock!
      raise NotConfirmable unless batch.confirmable?

      allowed = Registry.fetch(batch.kind).importer_class.new(company_id: batch.company_id).duplicate_modes
      raise DuplicateModeNotAllowed.new(allowed:) unless allowed.include?(duplicate_mode)
      raise NothingToImport if batch.ready_count.zero?

      queue(batch, duplicate_mode)
      ProcessChunk.request(batch)
      Audit.record(action: "import.confirmed", subject: batch, metadata: { kind: batch.kind, duplicate_mode:, ready_count: batch.ready_count })
      batch
    end

    def queue(batch, duplicate_mode)
      ApplicationRecord.transaction(requires_new: true) { batch.update!(status: "queued", duplicate_mode:, confirmed_at: Time.current) }
    rescue ActiveRecord::RecordNotUnique
      batch.restore_attributes
      raise AlreadyRunning
    end
  end
end
