module Idempotency
  # System job (no organization): deletes expired idempotency_keys of all organizations.
  class PurgeExpiredJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform = Purge.expired
  end
end
