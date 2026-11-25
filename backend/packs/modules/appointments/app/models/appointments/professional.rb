module Appointments
  # A person who attends clients, as a record of ONE company. TENANT table scoped to the COMPANY; only ids are stored (no
  # association to the private Tenancy and Identity models). `user_id` optionally links the record to a user, who must have a
  # membership in the organization; the same user may have a record in several companies, but only one non-archived in each. Never
  # destroyed: it is archived (`archived_at`) so history can keep referencing it.
  #
  # The contact (phone_e164, email) is personal data: deterministic ciphertext, masked in the audit trail.
  class Professional < ApplicationRecord
    MAX_NAME_LENGTH = 120
    MAX_EMAIL_LENGTH = 254
    # What a client may write; the audit trail records these plus `archived_at`.
    EDITABLE = %w[display_name user_id active phone_e164 email].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    encrypts :phone_e164, deterministic: true
    encrypts :email, deterministic: true, downcase: true

    has_many :branch_assignments, class_name: "Appointments::ProfessionalBranchAssignment", dependent: :restrict_with_exception
    has_many :professional_services, class_name: "Appointments::ProfessionalService", dependent: :restrict_with_exception

    before_validation :normalize_fields

    validates :display_name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :active, inclusion: { in: [ true, false ] }
    # Translates the partial unique index (one non-archived record per person in a company) into a field error.
    validates :user_id, uniqueness: { scope: :company_id, conditions: -> { where(archived_at: nil) } }, allow_nil: true,
                        unless: -> { archived? || user_id_locked? }
    validate :user_id_not_reassigned
    validate :user_id_is_uuid, unless: :user_id_locked?
    validate :company_exists
    validate :user_is_member, if: -> { user_id.present? && (new_record? || user_id_changed?) && !user_id_locked? }
    validate :phone_is_a_real_number, if: :phone_needs_checking?
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: MAX_EMAIL_LENGTH }, allow_nil: true

    # What management lists: everything not archived, paused professionals included.
    scope :unarchived, -> { where(archived_at: nil) }
    # What can be offered for booking: not archived and not paused.
    scope :active, -> { unarchived.where(active: true) }
    # Who works at the branch, among the branch's company's professionals.
    scope :assigned_to, ->(branch) {
      where(company_id: branch.company_id,
            id: ProfessionalBranchAssignment.where(company_id: branch.company_id, branch_id: branch.id).select(:professional_id))
    }
    # The records of one person (user) assigned to the branch; none for a blank user, so an unlinked record never matches.
    scope :of_user, ->(user_id, branch:) { user_id.blank? ? none : assigned_to(branch).where(user_id:) }

    def archived? = !archived_at.nil?

    # Ids of the branches and services; read from the loaded associations, so a listing preloads them once.
    def branch_ids = branch_assignments.map(&:branch_id).sort
    def service_ids = professional_services.map(&:service_id).sort

    # Is this the user's OWN record, and does it attend in the branch? What lets a person see and manage what is theirs.
    def own_in_branch?(user_id:, branch_id:) = user_id.present? && self.user_id == user_id && branch_assignments.exists?(branch_id:)

    # Can a branch-level manager take them in? Yes when they work nowhere yet or already work in that branch.
    def available_to_branch?(branch_id) = branch_assignments.none? || branch_assignments.exists?(branch_id:)

    private

    def normalize_fields
      self.display_name = display_name.strip if display_name
      self.email = email.strip.presence if email
      self.phone_e164 = phone_e164.presence if phone_e164
      return unless phone_needs_checking?

      normalized = Customers::Phone.normalize(phone_e164, region: Current.context.organization.country_code)
      self.phone_e164 = normalized if normalized
    end

    # Blank phones are nil by now, so a record without one (the CSV import) never needs the organization's country. A stored
    # number is not revalidated on unrelated saves.
    def phone_needs_checking? = !phone_e164.nil? && (new_record? || phone_e164_changed?)

    # Reported on `phone`, the name the API reads and writes, so a 422 points at the field the client sent.
    def phone_is_a_real_number
      errors.add(:phone, :invalid) unless Customers::Phone.normalize(phone_e164, region: Current.context.organization.country_code)
    end

    # The error message reads the attribute it is reported on.
    def phone = phone_e164

    # Once linked, the person is fixed (to change it, archive and create another record): a different user, null or anything
    # malformed are all the same refusal, so the link can neither be swapped nor dropped.
    def user_id_locked? = persisted? && user_id_in_database.present? && user_id_changed?

    def user_id_not_reassigned
      errors.add(:user_id, :immutable) if user_id_locked?
    end

    # The uuid cast turns anything malformed into nil, which would silently unlink an unlinked-to-be record.
    def user_id_is_uuid
      errors.add(:user_id, :invalid) if user_id.nil? && !user_id_before_type_cast.nil?
    end

    def company_exists
      errors.add(:company_id, :invalid) if company_id.blank? || Tenancy::Directory.companies.where(id: company_id).none?
    end

    def user_is_member
      errors.add(:user_id, :invalid) unless Access.member?(user_id:, organization_id:)
    end
  end
end
