module Events
  # A DeliverJob asks for a subscriber this process has not registered (e.g. a deploy removed it while deliveries were
  # queued). Sidekiq retries, so the delivery completes if the subscriber comes back.
  class UnknownSubscriber < Error
    def initialize(event_name, subscriber)
      super("El suscriptor #{subscriber.inspect} no está registrado para #{event_name}")
    end
  end
end
