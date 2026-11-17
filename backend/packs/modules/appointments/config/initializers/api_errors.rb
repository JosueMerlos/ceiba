# Appointments errors the API translates to problem+json (see Api::ErrorRegistry). `to_prepare` re-registers after every code
# reload in development.
Rails.application.config.to_prepare do
  # Each field error carries its translated message, under the use case's scope of the locale.
  field_errors = ->(scope) {
    ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.#{scope}.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    }
  }

  Api::ErrorRegistry.register(Appointments::Availability::InvalidRequest, status: :unprocessable_content, code: "appointments.availability_invalid",
    errors: field_errors.call("availability"))
  Api::ErrorRegistry.register(Appointments::SlotUnavailable, status: :conflict, code: "appointments.slot_unavailable")
  Api::ErrorRegistry.register(Appointments::PersonUnavailable, status: :conflict, code: "appointments.person_unavailable")
  Api::ErrorRegistry.register(Appointments::InvalidBooking, status: :unprocessable_content, code: "appointments.booking_invalid",
    errors: field_errors.call("booking"))
  Api::ErrorRegistry.register(Appointments::InvalidTransition, status: :conflict, code: "appointments.invalid_transition",
    errors: field_errors.call("transition"))
  Api::ErrorRegistry.register(Appointments::InvalidCancellation, status: :unprocessable_content, code: "appointments.cancellation_invalid",
    errors: field_errors.call("cancellation"))
  Api::ErrorRegistry.register(Appointments::Agenda::InvalidRequest, status: :unprocessable_content, code: "appointments.agenda_invalid",
    errors: field_errors.call("agenda"))
end
