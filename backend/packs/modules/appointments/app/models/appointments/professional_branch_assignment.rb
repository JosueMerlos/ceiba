module Appointments
  # A branch where a professional attends. TENANT table; the composite foreign keys already force the professional and the
  # branch to belong to this company, the model reports it as a field error first.
  class ProfessionalBranchAssignment < ApplicationRecord
    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Optional: a missing professional is reported as a field error by `professional_in_company`, not as "must exist".
    belongs_to :professional, class_name: "Appointments::Professional", optional: true

    validates :branch_id, uniqueness: { scope: :professional_id }, if: -> { branch_id.present? && professional_id.present? }
    validate :branch_in_company
    validate :professional_in_company
    validate :professional_not_archived, on: :create

    private

    def branch_in_company
      errors.add(:branch_id, :invalid) if branch_id.blank? || Tenancy::Directory.branch_company_id(branch_id) != company_id
    end

    def professional_in_company
      errors.add(:professional_id, :invalid) if professional&.company_id != company_id
    end

    # Archived professionals keep the assignments they had; they take no new ones.
    def professional_not_archived
      errors.add(:base, :archived) if professional&.archived?
    end
  end
end
