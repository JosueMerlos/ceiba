module Appointments
  # The availability answer the public endpoint serves: the serialized body, computed from the use case. Must run inside a tenant context.
  module PublicAvailability
    module_function

    def call(company:, branch:, services:, professional:, from_date:, to_date:)
      result = Availability.call(company:, branch:, services:, professional:, from_date:, to_date:)
      AvailabilityResponse.call(result, time_zone: branch.time_zone)
    end
  end
end
