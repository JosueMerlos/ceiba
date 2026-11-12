require "digest"

module Appointments
  # The availability answer the public endpoint serves: the serialized body, cached for a short time because the booking page
  # is hit by many anonymous visitors asking the same thing. It runs AFTER the endpoint's doors (company, module, booking
  # enabled, branch), so a closed door is never served from here; only the 200 body is stored, an error raises out of the
  # block and nothing is written. Must run inside a tenant context.
  module PublicAvailability
    TTL = 30.seconds

    module_function

    def call(company:, branch:, services:, professional:, from_date:, to_date:)
      key = cache_key(company:, branch:, services:, professional:, from_date:, to_date:)
      Rails.cache.fetch(key, expires_in: TTL) do
        result = Availability.call(company:, branch:, services:, professional:, from_date:, to_date:)
        AvailabilityResponse.call(result, time_zone: branch.time_zone)
      end
    end

    # The company in the clear (a namespace per tenant); the rest of the request as a digest. The order of the services is part
    # of the key: it is the sequence, and the block lasts and prices differently.
    def cache_key(company:, branch:, services:, professional:, from_date:, to_date:)
      asked = [ branch.id, services.map(&:id).join(","), professional == :any ? "any" : professional.id, from_date.iso8601, to_date.iso8601 ]
      "appointments/public-availability/v1/#{company.id}/#{Digest::SHA256.hexdigest(asked.join('|'))}"
    end
    private_class_method :cache_key
  end
end
