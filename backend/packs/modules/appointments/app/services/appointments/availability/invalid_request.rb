module Appointments
  module Availability
    # The request cannot be answered as asked (an inactive professional, a service nobody provides, a bad range). `errors`
    # is a list of { field:, code: } so a caller can report every problem at once.
    class InvalidRequest < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors.freeze
        super(errors.map { "#{it[:field]}: #{it[:code]}" }.join(", "))
      end
    end
  end
end
