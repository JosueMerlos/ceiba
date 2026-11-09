# Sentry en el backend (M0.13, docs/architecture/10-infrastructure.md §Observabilidad). La configuración vive aquí (no en el
# initializer) para probarla con un transporte falso; config/initializers/sentry.rb solo llama a SentrySetup.init.
#
#   SENTRY_DSN          sin él Sentry queda inactivo (desarrollo local, test, CI)
#   SENTRY_ENVIRONMENT  nombre del entorno en Sentry (production, staging...); por defecto Rails.env
#   APP_RELEASE         identificador del despliegue (p. ej. el SHA del commit); aparece como release
#
# Reglas de privacidad: sin PII por defecto (send_default_pii false: ni cuerpos, ni cookies, ni IP, ni usuario); `before_send`
# quita los correos de los mensajes, filtra los datos extra con config.filter_parameters y retira los argumentos de los jobs.
# En test queda desactivado aunque llegue un DSN.
require "sentry-ruby"
require "sentry-rails"
require "sentry-sidekiq"

module SentrySetup
  EMAIL = /[\w.+%-]+@[\w-]+(?:\.[\w-]+)+/
  TENANT_TAGS = {
    organization_id: ->(fields, _log) { fields[:organization_id] },
    company_id: ->(fields, _log) { fields[:company_id] },
    branch_id: ->(fields, _log) { fields[:branch_id] },
    principal_type: ->(fields, _log) { fields[:principal_type] },
    principal_id: ->(fields, _log) { fields[:principal_id] },
    job: ->(_fields, log) { log.job_class }
  }.freeze

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
    config.rails.register_error_subscriber = true # los 500 los rescata Api::ErrorHandling y los reporta con Rails.error
    config.before_send = method(:before_send)
  end

  def before_send(event, _hint = nil)
    event.tags.merge!(tenant_tags)
    scrub(event)
    event
  end

  # Solo identificadores, nunca el correo ni el nombre (misma fuente que el log: Observability::LogFields).
  def tenant_tags
    fields = Observability::LogFields.current
    TENANT_TAGS.transform_values { |source| source.call(fields, Observability::LogContext) }.compact
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

  # sentry-sidekiq adjunta el job entero al contexto; sus args pueden llevar datos personales.
  def redact_job_args(context)
    return context unless context.is_a?(Hash) && (context.key?(:args) || context.key?("args"))

    context.merge(args: "[FILTERED]").except("args")
  end
end
