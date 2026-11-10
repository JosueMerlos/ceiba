module Events
  # Reported when the outbox has gone too long without publishing. The message is FIXED on purpose: Sentry groups by
  # type and message, and the figures (which change every minute) would split the alert into countless issues; they go
  # in the report context.
  class OutboxLagExceeded < StandardError
    def initialize(message = "El outbox tiene eventos sin publicar desde hace más de 5 minutos") = super
  end
end
