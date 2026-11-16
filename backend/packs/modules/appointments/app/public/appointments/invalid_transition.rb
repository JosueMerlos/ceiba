module Appointments
  # The appointment is not in a status the action can start from (somebody changed it first, or it already ended), or the action
  # is too early (a no-show before the start). The client refreshes the appointment. `errors` is a list of { field:, code: }.
  class InvalidTransition < StandardError
    attr_reader :errors

    def initialize(code)
      @errors = [ { field: :status, code: } ].freeze
      super("status: #{code}")
    end
  end
end
