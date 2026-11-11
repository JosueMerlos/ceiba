module Customers
  # Phone numbers are stored in E.164 so the same person matches whatever format the staff or the booking form typed.
  module Phone
    module_function

    # `region` is the ISO country code the number is assumed to belong to when it has no international prefix.
    # Returns the E.164 string, or nil when the value is not a valid number.
    def normalize(raw, region:)
      return if raw.blank?

      parsed = Phonelib.parse(raw.to_s, region)
      parsed.e164 if parsed.valid?
    end
  end
end
