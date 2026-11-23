module Imports
  # Purges one organization's expired previews and stuck batches (the tenant middleware opens its context). Idempotent:
  # a second run finds nothing due.
  class PurgeOrganizationJob
    include Sidekiq::Job

    sidekiq_options queue: "low"

    def perform = Purge.call
  end
end
