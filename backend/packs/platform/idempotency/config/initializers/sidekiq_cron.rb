# Scheduled jobs are registered when the Sidekiq process boots (not in web or console).
Sidekiq.configure_server do |config|
  config.on(:startup) { Idempotency::Schedule.load! }
end
