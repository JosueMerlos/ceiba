module Events
  # A registered subscriber: who (`subscriber`, unique per event and the idempotency key), which event, which handler
  # (`call(Events::Event)`) and which queue it is delivered on.
  Subscription = Data.define(:event_name, :subscriber, :handler, :queue)
end
