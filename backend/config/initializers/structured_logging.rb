# Structured logs: lograge (one line per request, with duration and status) plus our own JSON formatter, instead of
# rails_semantic_logger. Semantic Logger replaces the whole Rails logger and brings its own writer thread; here only one
# line per request and per job with fixed fields is needed, and other logs (development SQL, warnings) stay as they are
# but in JSON. Fewer pieces, less surface.
#
# Request params are NOT logged (not even filtered): the filter is a safety net, not an authorization.
Rails.application.configure do
  config.lograge.enabled = true
  # The logger's formatter (Observability::JsonLogFormatter) serializes the Hash, so it is not encoded twice.
  config.lograge.formatter = ->(data) { data }

  # The API inherits from ActionController::API, not Base (lograge's default).
  config.lograge.base_controller_class = "ActionController::API"

  config.lograge.custom_payload_method = lambda do |controller|
    Observability::LogFields.current.merge(Observability::LogFields.request(controller.request))
  end

  # Infrastructure probes hit every few seconds: their line is just noise.
  silenced_paths = %w[/api/health /api/ready].freeze
  config.lograge.ignore_custom = ->(event) { silenced_paths.include?(event.payload[:path].to_s.split("?").first) }
end

# No ANSI color codes: they would break each JSON line (development SQL carries them).
ActiveSupport::LogSubscriber.colorize_logging = false

# app/ constants cannot be used while an initializer loads (Zeitwerk is not ready): they go in to_prepare, which re-runs
# after every code reload in development.
Rails.application.config.to_prepare do
  # One JSON line for all other messages too (the [request_id] log tag would break the JSON: it is already a field).
  Rails.logger.formatter = Observability::JsonLogFormatter.new

  Tenancy.singleton_class.prepend(Observability::TenancyHook) unless Tenancy.singleton_class.include?(Observability::TenancyHook)
end
