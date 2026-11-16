module Appointments
  # The cancellation request itself is wrong (a reason missing or outside the list). `errors` is a list of { field:, code: }.
  class InvalidCancellation < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.freeze
      super(errors.map { "#{it[:field]}: #{it[:code]}" }.join(", "))
    end
  end
end
