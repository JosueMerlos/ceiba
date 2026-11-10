# Job logs use the same JSON schema as request logs.
require Rails.root.join("config/middleware/job_observability").to_s

Sidekiq.configure_server { |config| JobObservability.install(config) }
