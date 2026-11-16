module Appointments
  # A request that is wrong in one or more fields. `errors` is a list of { field:, code: } so a caller can report every problem at
  # once; the API registers each subclass with its own code and message scope.
  class FieldErrors < StandardError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.freeze
      super(errors.map { "#{it[:field]}: #{it[:code]}" }.join(", "))
    end
  end
end
