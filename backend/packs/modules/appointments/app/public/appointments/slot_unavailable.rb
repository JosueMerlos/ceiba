module Appointments
  # The slot cannot be booked: the engine no longer offers that start (somebody took it first, the hours changed) or the database
  # refused the overlap. The client picks another time.
  class SlotUnavailable < StandardError
    def initialize(message = "the slot is no longer available") = super
  end
end
