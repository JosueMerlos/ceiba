module Imports
  # System job (no organization): finds the organizations with expired previews or stuck batches and enqueues one
  # PurgeOrganizationJob per organization, which does the writing inside that tenant.
  class PurgeExpiredJob
    include Sidekiq::Job

    sidekiq_options queue: "low", tenant: false

    def perform
      Purge.due_organization_ids.each do |organization_id|
        Sidekiq::Client.push("class" => PurgeOrganizationJob, "queue" => "low", "organization_id" => organization_id, "args" => [])
      end
    end
  end
end
