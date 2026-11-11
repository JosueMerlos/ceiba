module Appointments
  # A service a professional performs. TENANT table; the composite foreign keys already force the professional and the
  # service to belong to this company, the model reports it as a field error first. An archived service cannot be linked
  # (a link that already exists stays when the service is archived later).
  class ProfessionalService < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Optional: a missing one is reported as a field error below, not as "must exist".
    belongs_to :professional, class_name: "Appointments::Professional", optional: true
    belongs_to :service, class_name: "Appointments::Service", optional: true

    validates :service_id, uniqueness: { scope: :professional_id }, if: -> { service_id.present? && professional_id.present? }
    validate :professional_in_company
    validate :service_in_company
    validate :service_not_archived, on: :create

    private

    def professional_in_company
      errors.add(:professional_id, :invalid) if professional&.company_id != company_id
    end

    def service_in_company
      errors.add(:service_id, :invalid) if service&.company_id != company_id
    end

    def service_not_archived
      errors.add(:service_id, :archived) if service&.archived?
    end
  end
end
