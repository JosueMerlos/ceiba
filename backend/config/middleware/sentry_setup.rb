# Backend Sentry configuration. It lives here (not in the initializer) so it can be tested with a fake transport; the
# initializer only calls SentrySetup.init.
#
#   SENTRY_DSN          without it Sentry is inactive (local development, test, CI)
#   SENTRY_ENVIRONMENT  environment name in Sentry (production, staging...); defaults to Rails.env
#   APP_RELEASE         deploy identifier (e.g. the commit SHA); shown as the release
#
# Privacy: no PII by default (send_default_pii false: no bodies, cookies, IP or user); `before_send` strips emails from
# messages, filters extra data with config.filter_parameters and removes job arguments. Disabled in test even with a DSN.
require "sentry-ruby"
require "sentry-rails"
require "sentry-sidekiq"

module SentrySetup
  EMAIL = /[\w.+%-]+@[\w-]+(?:\.[\w-]+)+/

  module_function

  def init(env: ENV, rails_env: Rails.env)
    Sentry.init { |config| configure(config, env:, rails_env:) }
  end

  def configure(config, env: ENV, rails_env: Rails.env)
    config.dsn = env["SENTRY_DSN"].presence
    config.environment = env["SENTRY_ENVIRONMENT"].presence || rails_env
    config.enabled_environments = rails_env.to_s == "test" ? [] : [ config.environment ]
    config.release = env["APP_RELEASE"].presence
    config.send_default_pii = false
    config.breadcrumbs_logger = []
    config.sdk_logger = Rails.logger # the SDK's internal log, in JSON like the rest (it defaults to plain text on STDOUT)
    config.auto_session_tracking = false # release health is unused; without this it warns on every boot if APP_RELEASE is missing
    config.rails.register_error_subscriber = true # 500s are rescued by Api::ErrorHandling and reported through Rails.error
    config.before_send = method(:before_send)
    install_event_processor
  end

  # `before_send` runs on the Sentry client's background thread, where the per-thread Current and LogContext are empty:
  # it can only scrub data. Tags are set by a global processor, which runs SYNCHRONOUSLY on capture, on the request or job
  # thread. Registered once (global processors accumulate across `Sentry.init`).
  def install_event_processor
    return if @processor_installed

    Sentry.add_global_event_processor { |event, _hint| add_tags(event) }
    @processor_installed = true
  end

  def add_tags(event)
    event.tags.merge!(tenant_tags(event)) if event.respond_to?(:tags)
    event
  end

  def before_send(event, _hint = nil)
    scrub(event)
    event
  end

  # Identifiers only, never the email or name (same source as the log). In a job the error is captured OUTSIDE
  # JobLogger#prepare (LogContext is already empty): organization and class are read from the `sidekiq` context that
  # sentry-sidekiq attaches with the whole job.
  def tenant_tags(event)
    fields = Observability::LogFields.current
    job = event.contexts.to_h.with_indifferent_access[:sidekiq] || {}
    {
      organization_id: fields[:organization_id] || job[:organization_id], company_id: fields[:company_id], branch_id: fields[:branch_id],
      principal_type: fields[:principal_type], principal_id: fields[:principal_id], request_id: Current.request_id,
      job: Observability::LogContext.job_class || job[:wrapped] || job[:class]
    }.compact
  end

  def scrub(event)
    event.message = scrub_text(event.message) if event.respond_to?(:message) && event.message
    event.exception&.values&.each { |exception| exception.value = scrub_text(exception.value) }
    event.extra = filter(event.extra)
    event.contexts = event.contexts.to_h.transform_values { |context| filter(redact_job_args(context)) }
  end

  def scrub_text(text) = text.to_s.gsub(EMAIL, "[email]")

  def filter(hash)
    return hash unless hash.is_a?(Hash)

    @filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    @filter.filter(hash.deep_stringify_keys).deep_symbolize_keys.transform_values { |value| value.is_a?(String) ? scrub_text(value) : value }
  end

  # sentry-sidekiq attaches the whole job to the context; its args may carry personal data.
  def redact_job_args(context)
    return context unless context.is_a?(Hash) && (context.key?(:args) || context.key?("args"))

    context.merge(args: "[FILTERED]").except("args")
  end
end
