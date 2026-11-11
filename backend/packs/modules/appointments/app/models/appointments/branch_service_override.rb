module Appointments
  # A branch's own duration and/or price for a company service. TENANT table; the composite foreign keys already force the
  # branch and the service to belong to this company, the model reports it as a field error first. The currency is the
  # service's, so it is not stored. At least one of the two values must be present.
  class BranchServiceOverride < ApplicationRecord
    EDITABLE = %w[duration_minutes price_minor].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Optional: a missing service is reported as a field error by `service_in_company`, not as "must exist".
    belongs_to :service, optional: true

    validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: Service::MAX_MINUTES }, allow_nil: true
    validates :price_minor, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: Service::MAX_PRICE_MINOR }, allow_nil: true
    validates :service_id, uniqueness: { scope: :branch_id }, if: -> { service_id.present? && branch_id.present? }
    validate :overrides_something
    validate :branch_in_company
    validate :service_in_company

    private

    def overrides_something
      errors.add(:base, :empty) if duration_minutes.nil? && price_minor.nil?
    end

    def branch_in_company
      errors.add(:branch_id, :invalid) if branch_id.blank? || Tenancy::Directory.branch_company_id(branch_id) != company_id
    end

    def service_in_company
      errors.add(:service_id, :invalid) if service&.company_id != company_id
    end
  end
end
