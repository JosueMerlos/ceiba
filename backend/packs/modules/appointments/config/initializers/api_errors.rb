# Appointments errors the API translates to problem+json (see Api::ErrorRegistry). `to_prepare` re-registers after every code
# reload in development.
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Appointments::Availability::InvalidRequest, status: :unprocessable_content, code: "appointments.availability_invalid",
    errors: ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.availability.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    })
  Api::ErrorRegistry.register(Appointments::SlotUnavailable, status: :conflict, code: "appointments.slot_unavailable")
  Api::ErrorRegistry.register(Appointments::PersonUnavailable, status: :conflict, code: "appointments.person_unavailable")
  Api::ErrorRegistry.register(Appointments::InvalidTransition, status: :conflict, code: "appointments.invalid_transition",
    errors: ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.transition.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    })
  Api::ErrorRegistry.register(Appointments::InvalidCancellation, status: :unprocessable_content, code: "appointments.cancellation_invalid",
    errors: ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.cancellation.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    })
  Api::ErrorRegistry.register(Appointments::InvalidBooking, status: :unprocessable_content, code: "appointments.booking_invalid",
    errors: ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.booking.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    })
end
