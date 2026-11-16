module Appointments
  # The professional's person (the same user) already has a blocking appointment that overlaps, in another company of the group.
  class PersonUnavailable < StandardError
    def initialize(message = "the person has another appointment at that time") = super
  end
end
