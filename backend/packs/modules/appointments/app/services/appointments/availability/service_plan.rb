module Appointments
  module Availability
    # What a request for several services amounts to, as plain values: the total duration, the buffers at the two edges of the
    # whole visit (preparation before the first service, cleanup after the last one), the total price and the resource kind
    # needed (nil when none). Overrides replace a service's own duration or price only where they are set (a price of 0 is a real override).
    # `lines` is the same plan per service (what a booking snapshots); the totals built by `call` are the sums of the lines.
    ServicePlan = Data.define(:duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency, :required_kind, :lines) do
      def initialize(lines: [], **rest) = super
      # `overrides` is { service_id => { duration_minutes:, price_minor: } }; services keep the order they were asked in. A visit can
      # need at most one kind of resource (eligibility rejects the rest), so more than one here is a caller bug.
      def self.call(services:, overrides:, currency:)
        lines = services.each_with_index.map do |service, position|
          own = overrides.fetch(service.id, {})
          ServicePlan::Line.new(service_id: service.id, position:, duration_minutes: own[:duration_minutes] || service.duration_minutes,
                   buffer_before_minutes: service.buffer_before_minutes, buffer_after_minutes: service.buffer_after_minutes,
                   price_minor: own[:price_minor] || service.price_minor, currency:)
        end
        kinds = services.flat_map(&:required_kinds).uniq
        raise ArgumentError, "a request can ask for at most one resource kind" if kinds.size > 1

        new(duration_minutes: lines.sum(&:duration_minutes), buffer_before_minutes: services.first.buffer_before_minutes,
            buffer_after_minutes: services.last.buffer_after_minutes, price_minor: lines.sum(&:price_minor), currency:,
            required_kind: kinds.first, lines:)
      end

      # The time the visit occupies, buffers included.
      def block_minutes = buffer_before_minutes + duration_minutes + buffer_after_minutes
    end

    # One service of the plan with its effective values: the own buffers and the override-aware duration and price.
    ServicePlan::Line = Data.define(:service_id, :position, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency)

    ServicePlan::Item = Data.define(:id, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :required_kinds) do
      def initialize(required_kinds: [], **rest) = super
    end
  end
end
