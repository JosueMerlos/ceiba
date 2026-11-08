module Events
  # Un DeliverJob pide un suscriptor que este proceso no tiene registrado (p. ej. un despliegue lo retiró mientras había
  # entregas en cola). Sidekiq reintenta: si el suscriptor vuelve, la entrega se completa.
  class UnknownSubscriber < Error
    def initialize(event_name, subscriber)
      super("El suscriptor #{subscriber.inspect} no está registrado para #{event_name}")
    end
  end
end
