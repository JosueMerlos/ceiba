module Appointments
  # The body of an availability answer, shared by the panel and the public endpoint. A plain Hash: the public endpoint caches it.
  module AvailabilityResponse
    module_function

    def call(result, time_zone:)
      plan = result.plan
      { data: AvailabilitySlotSerializer.new(result.slots).serializable_hash,
        meta: { time_zone:, duration_minutes: plan.duration_minutes, buffer_before_minutes: plan.buffer_before_minutes,
                buffer_after_minutes: plan.buffer_after_minutes, price: { amount_minor: plan.price_minor, currency: plan.currency },
                step_minutes: result.step_minutes } }
    end
  end
end
