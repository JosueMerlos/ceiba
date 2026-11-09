# Logs de los jobs (M0.13): mismo esquema JSON que las requests. Ver config/middleware/job_observability.rb.
require Rails.root.join("config/middleware/job_observability").to_s

Sidekiq.configure_server { |config| JobObservability.install(config) }
