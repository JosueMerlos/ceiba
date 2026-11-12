module Appointments
  module PublicAvailability
    # Any door of the anonymous endpoint being shut. One error and one message whatever the reason, so nothing tells a closed
    # company from a missing one. It is a 404 through the API's registry.
    class Closed < ActiveRecord::RecordNotFound
      def initialize(message = "No se encontró el recurso") = super
    end
  end
end
