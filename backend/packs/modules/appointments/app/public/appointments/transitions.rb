module Appointments
  # The appointment state machine, as data: the only place that knows which status each action leads to, from which statuses,
  # what it publishes, whether a professional may do it on their own appointments (`own?`, with the update_own permission; every
  # action is open to the staff permission) and whether the appointment must have started. Appointments::Transition applies it.
  module Transitions
    STAFF_PERMISSION = "appointments.appointment.update".freeze
    OWN_PERMISSION = "appointments.appointment.update_own".freeze

    Rule = Data.define(:action, :to, :from, :event, :own, :attributes, :not_before_start) do
      def own? = own
      def not_before_start? = not_before_start
    end

    ACTIVE = %w[scheduled confirmed].freeze

    RULES = [
      Rule.new(action: :confirm, to: "confirmed", from: %w[scheduled], event: "appointments.appointment_confirmed.v1", own: true,
               attributes: [], not_before_start: false),
      Rule.new(action: :check_in, to: "checked_in", from: ACTIVE, event: "appointments.appointment_checked_in.v1", own: true,
               attributes: [], not_before_start: false),
      Rule.new(action: :complete, to: "completed", from: %w[checked_in], event: "appointments.appointment_completed.v1", own: true,
               attributes: [], not_before_start: false),
      # Nobody can miss an appointment that has not started yet.
      Rule.new(action: :no_show, to: "no_show", from: ACTIVE, event: "appointments.appointment_no_show.v1", own: true,
               attributes: [], not_before_start: true),
      Rule.new(action: :cancel, to: "cancelled", from: ACTIVE, event: "appointments.appointment_cancelled.v1", own: false,
               attributes: %i[cancelled_by cancellation_reason], not_before_start: false),
      Rule.new(action: :reschedule, to: "rescheduled", from: ACTIVE, event: "appointments.appointment_rescheduled.v1", own: false,
               attributes: [], not_before_start: false)
    ].index_by(&:action).freeze

    def self.fetch(action) = RULES.fetch(action.to_sym) { raise ArgumentError, "unknown appointment action: #{action}" }

    def self.actions = RULES.keys

    def self.allowed?(from:, to:) = RULES.each_value.any? { it.to == to && it.from.include?(from) }

    def self.events = RULES.each_value.map(&:event)
  end
end
