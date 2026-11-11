module Appointments
  # A person who attends clients, as a record of ONE company. TENANT table scoped to the COMPANY; only ids are stored (no
  # association to the private Tenancy and Identity models). `user_id` optionally links the record to a user, who must have a
  # membership in the organization; the same user may have a record in several companies, but only one in each. Never
  # destroyed: it is archived (`archived_at`) so history can keep referencing it.
  class Professional < ApplicationRecord
    MAX_NAME_LENGTH = 120
    # What a client may write; the audit trail records these plus `archived_at`.
    EDITABLE = %w[display_name user_id active].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    has_many :branch_assignments, class_name: "Appointments::ProfessionalBranchAssignment", dependent: :restrict_with_exception
    has_many :professional_services, class_name: "Appointments::ProfessionalService", dependent: :restrict_with_exception

    before_validation :normalize_fields

    validates :display_name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :active, inclusion: { in: [ true, false ] }
    # Translates the partial unique index (one record per person in a company) into a field error.
    validates :user_id, uniqueness: { scope: :company_id }, allow_nil: true
    validate :company_exists
    validate :user_is_member, if: -> { user_id.present? && (new_record? || user_id_changed?) }

    # What management lists: everything not archived, paused professionals included.
    scope :unarchived, -> { where(archived_at: nil) }
    # What can be offered for booking: not archived and not paused.
    scope :active, -> { unarchived.where(active: true) }

    def archived? = !archived_at.nil?

    # Ids of the branches and services; read from the loaded associations, so a listing preloads them once.
    def branch_ids = branch_assignments.map(&:branch_id).sort
    def service_ids = professional_services.map(&:service_id).sort

    # Is this the user's OWN record, and does it attend in the branch? What lets a person see and manage what is theirs.
    def own_in_branch?(user_id:, branch_id:) = user_id.present? && self.user_id == user_id && branch_assignments.exists?(branch_id:)

    private

    def normalize_fields
      self.display_name = display_name.strip if display_name
    end

    def company_exists
      errors.add(:company_id, :invalid) if company_id.blank? || Tenancy::Directory.companies.where(id: company_id).none?
    end

    def user_is_member
      errors.add(:user_id, :invalid) unless Access.member?(user_id:, organization_id:)
    end
  end
end
