module Events
  class InvalidPayload < Error
    attr_reader :event_name, :violations

    def initialize(event_name, violations)
      @event_name = event_name
      @violations = violations
      super("El payload de #{event_name} no cumple su esquema: #{violations.join('; ')}")
    end
  end
end
