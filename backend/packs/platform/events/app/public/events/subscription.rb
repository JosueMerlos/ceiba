module Events
  # Un suscriptor registrado: quién (`subscriber`, único por evento y clave de la idempotencia), a qué evento, con qué
  # handler (`call(Events::Event)`) y en qué cola se entrega.
  Subscription = Data.define(:event_name, :subscriber, :handler, :queue)
end
