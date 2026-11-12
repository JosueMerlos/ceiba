# Appointments errors the API translates to problem+json (see Api::ErrorRegistry). `to_prepare` re-registers after every code
# reload in development.
Rails.application.config.to_prepare do
  Api::ErrorRegistry.register(Appointments::Availability::InvalidRequest, status: :unprocessable_content, code: "appointments.availability_invalid",
    errors: ->(error) {
      error.errors.map do |entry|
        { field: entry[:field].to_s, code: entry[:code].to_s, message: I18n.t("appointments.availability.errors.#{entry[:field]}.#{entry[:code]}") }
      end
    })
end
