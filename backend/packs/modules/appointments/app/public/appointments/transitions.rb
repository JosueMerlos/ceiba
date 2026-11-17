module Appointments
  # The appointment state machine, as data: the only place that knows which status each action leads to, from which statuses,
  # what it publishes, whether a professional may do it on their own appointments (`own?`, with update_own; every action is open
  # to the staff's update permission, see AppointmentPolicy) and whether the appointment must have started. Transition applies it.
  module Transitions
    Rule = Data.define(:action, :to, :from, :event, :own, :attributes, :not_before_start) do
      def initialize(attributes: [], not_before_start: false, **) = super

      def own? = own
      def not_before_start? = not_before_start
    end

    ACTIVE = %w[scheduled confirmed].freeze

    RULES = [
      Rule.new(action: :confirm, to: "confirmed", from: %w[scheduled], event: "appointments.appointment_confirmed.v1", own: true),
      Rule.new(action: :check_in, to: "checked_in", from: ACTIVE, event: "appointments.appointment_checked_in.v1", own: true),
      Rule.new(action: :complete, to: "completed", from: %w[checked_in], event: "appointments.appointment_completed.v1", own: true),
      # Nobody can miss an appointment that has not started yet.
      Rule.new(action: :no_show, to: "no_show", from: ACTIVE, event: "appointments.appointment_no_show.v1", own: true, not_before_start: true),
      Rule.new(action: :cancel, to: "cancelled", from: ACTIVE, event: "appointments.appointment_cancelled.v1", own: false,
               attributes: %i[cancelled_by cancellation_reason]),
      Rule.new(action: :reschedule, to: "rescheduled", from: ACTIVE, event: "appointments.appointment_rescheduled.v1", own: false)
    ].index_by(&:action).freeze

    def self.fetch(action) = RULES.fetch(action.to_sym) { raise ArgumentError, "unknown appointment action: #{action}" }

    def self.actions = RULES.keys

    def self.allowed?(from:, to:) = RULES.each_value.any? { it.to == to && it.from.include?(from) }

    def self.events = RULES.each_value.map(&:event)
  end
end
