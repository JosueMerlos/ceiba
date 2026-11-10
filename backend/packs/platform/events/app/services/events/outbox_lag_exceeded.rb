module Events
  # Lo que se reporta cuando el outbox lleva demasiado sin publicar. Mensaje FIJO a propósito: Sentry agrupa por tipo y mensaje,
  # y las cifras (que cambian cada minuto) irían a partir la alerta en mil incidencias; van en el contexto del reporte.
  class OutboxLagExceeded < StandardError
    def initialize(message = "El outbox tiene eventos sin publicar desde hace más de 5 minutos") = super
  end
end
