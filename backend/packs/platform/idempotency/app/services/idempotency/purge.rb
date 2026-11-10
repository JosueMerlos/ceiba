module Idempotency
  # Retention of idempotency_keys: an expired key (24 h) is useless and holds a business response. Deleted in batches
  # (no giant transaction or long locks), across all organizations.
  module Purge
    BATCH_SIZE = 1_000

    module_function

    def expired(now: Time.current)
      total = 0
      CrossTenant.run do
        loop do
          deleted = Key.where(id: Key.expired(now).limit(BATCH_SIZE).select(:id)).delete_all
          total += deleted
          break if deleted < BATCH_SIZE
        end
      end
      total
    end
  end
end
