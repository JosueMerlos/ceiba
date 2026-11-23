module Imports
  # Purges one expired preview or stuck batch (the tenant middleware opens its context and its transaction). Idempotent:
  # a batch no longer due is left alone.
  class PurgeBatchJob
    include Sidekiq::Job

    sidekiq_options queue: "low"

    def perform(batch_id) = Purge.call(batch_id:)
  end
end
