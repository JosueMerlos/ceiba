module Appointments
  # An override is authorized by its EFFECTIVE change, at the scope of the branch the route names. The record is the
  # override as it would end up (current row plus the requested change, not yet saved): an attribute is a change only if its
  # value differs from the row's, so resending the current price is not a price change, and clearing one is.
  class ServiceOverridePolicy < Access::BasePolicy
    def upsert?
      allowed = (!record.duration_minutes_changed? || can_change_duration?) && (!record.price_minor_changed? || can_change_price?)
      # A request that changes nothing still needs some override permission, so it reveals nothing to anyone else.
      allowed && (changing_a_value? || can_change_something?)
    end

    # Removing an override changes every value it holds back to the service's own.
    def destroy?
      (record.duration_minutes.nil? || can_change_duration?) && (record.price_minor.nil? || can_change_price?) && can_change_something?
    end

    private

    def changing_a_value? = record.duration_minutes_changed? || record.price_minor_changed?

    def can_change_duration? = can?("appointments.service.override_duration", context_scope(:branch))

    def can_change_price? = can?("appointments.service.override_price", context_scope(:branch))

    def can_change_something? = can_change_duration? || can_change_price?
  end
end
