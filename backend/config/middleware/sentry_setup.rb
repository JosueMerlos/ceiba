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
    config.sdk_logger = Rails.logger # el log interno del SDK, en JSON como el resto (por defecto escribe texto plano en STDOUT)
    config.auto_session_tracking = false # release health no se usa; sin esto avisa en cada arranque si falta APP_RELEASE
    config.rails.register_error_subscriber = true # los 500 los rescata Api::ErrorHandling y los reporta con Rails.error
    config.before_send = method(:before_send)
    install_event_processor
  end

  # `before_send` corre en el hilo de fondo del cliente de Sentry, donde Current y LogContext (por hilo) están vacíos: solo
  # sirve para limpiar datos. Los tags se ponen con un procesador global, que corre SÍNCRONO al capturar, en el hilo de la
  # request o del job. Se registra una sola vez (los procesadores globales se acumulan entre `Sentry.init`).
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

  # Solo identificadores, nunca el correo ni el nombre (misma fuente que el log: Observability::LogFields). En un job el error
  # se captura FUERA de JobLogger#prepare (LogContext ya está vacío): organización y clase se leen del contexto `sidekiq`
  # que sentry-sidekiq adjunta con el job entero.
  def tenant_tags(event)
    fields = Observability::LogFields.current
    job = event.contexts.to_h.with_indifferent_access[:sidekiq] || {}
    {
      organization_id: fields[:organization_id] || job[:organization_id], company_id: fields[:company_id], branch_id: fields[:branch_id],
      principal_type: fields[:principal_type], principal_id: fields[:principal_id],
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

  # sentry-sidekiq adjunta el job entero al contexto; sus args pueden llevar datos personales.
  def redact_job_args(context)
    return context unless context.is_a?(Hash) && (context.key?(:args) || context.key?("args"))

    context.merge(args: "[FILTERED]").except("args")
  end
end
