module Imports
  # System job (no organization): finds the expired previews and stuck batches and enqueues one PurgeBatchJob per batch,
  # which does the writing inside that batch's tenant.
  class PurgeExpiredJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform
      Purge.due.each do |organization_id, batch_id|
        Sidekiq::Client.push("class" => PurgeBatchJob, "queue" => "low", "organization_id" => organization_id, "args" => [ batch_id ])
      end
    end
  end
end
