module Appointments
  # The booking request itself is wrong (customer, source, notes, start, professional). `errors` is a list of { field:, code: } so a
  # caller can report every problem at once.
  class InvalidBooking < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.freeze
      super(errors.map { "#{it[:field]}: #{it[:code]}" }.join(", "))
    end
  end
end
