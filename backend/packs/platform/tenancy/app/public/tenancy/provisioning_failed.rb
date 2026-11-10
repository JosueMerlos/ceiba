module Tenancy
  # Provisioning could not complete and NOTHING was left half-done. A DOMAIN error (not a database exception): `code` says
  # why and `message` is readable for whoever operates.
  #
  #   :slug_reserved  the slug is a reserved word (admin, api...)
  #   :slug_taken     another company already uses the slug (includes the race between two simultaneous provisions)
  #   :invalid        other invalid data; `details` breaks it down by section and field
  class ProvisioningFailed < Error
    attr_reader :code, :details

    def initialize(code, message, details: {})
      super(message)
      @code = code
      @details = details.freeze
    end
  end
end
