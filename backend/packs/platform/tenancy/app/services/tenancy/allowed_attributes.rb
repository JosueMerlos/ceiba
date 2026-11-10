module Tenancy
  # Allowlist of attributes the public API accepts from callers (ProvisionOrganization, AddCompany, AddBranch). No id, status,
  # organization_id, timestamps...: they are rejected with ArgumentError instead of being silently assigned.
  module AllowedAttributes
    ORGANIZATION = %i[name legal_name country_code].freeze
    COMPANY = %i[name slug business_type currency locale].freeze
    BRANCH = %i[name time_zone address phone_e164].freeze

    module_function

    def permit(attributes, allowed, section)
      attributes = attributes.to_h.symbolize_keys
      unknown = attributes.keys - allowed
      raise ArgumentError, "Claves no permitidas en #{section}: #{unknown.join(', ')}" if unknown.any?

      attributes
    end
  end
end
