module Appointments
  module Availability
    # What a request for several services amounts to, as plain values: the total duration, the buffers at the two edges of the
    # whole visit (preparation before the first service, cleanup after the last one), the total price and the resource kinds
    # needed. Overrides replace a service's own duration or price only where they are set (a price of 0 is a real override).
    ServicePlan = Data.define(:duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency, :required_kinds) do
      # `overrides` is { service_id => { duration_minutes:, price_minor: } }; services keep the order they were asked in.
      def self.call(services:, overrides:, currency:)
        effective = services.map { |service| overrides.fetch(service.id, {}).then { |own| [ own[:duration_minutes] || service.duration_minutes, own[:price_minor] || service.price_minor ] } }
        new(duration_minutes: effective.sum(&:first), buffer_before_minutes: services.first.buffer_before_minutes,
            buffer_after_minutes: services.last.buffer_after_minutes, price_minor: effective.sum(&:last), currency:,
            required_kinds: services.flat_map(&:required_kinds).uniq.sort)
      end

      # The time the visit occupies, buffers included.
      def block_minutes = buffer_before_minutes + duration_minutes + buffer_after_minutes
    end

    ServicePlan::Item = Data.define(:id, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :required_kinds) do
      def initialize(required_kinds: [], **rest) = super
    end
  end
end
