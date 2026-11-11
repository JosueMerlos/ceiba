module Appointments
  # "This service needs a resource of this kind in the branch". TENANT table; the composite foreign key already forces the
  # service to belong to this company, the model reports it as a field error first.
  class ServiceResourceRequirement < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Optional: a missing service is reported as a field error below, not as "must exist".
    belongs_to :service, class_name: "Appointments::Service", optional: true

    validates :kind, inclusion: { in: Resource::KINDS }
    validates :kind, uniqueness: { scope: :service_id }, if: -> { kind.present? && service_id.present? }
    validate :service_in_company

    private

    def service_in_company
      errors.add(:service_id, :invalid) if service&.company_id != company_id
    end
  end
end
