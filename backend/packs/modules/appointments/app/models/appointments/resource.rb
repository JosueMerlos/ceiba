module Appointments
  # A physical resource of ONE branch (chair, room, equipment). TENANT table; only ids are stored (no association to the
  # private Tenancy models). Never destroyed: it is archived (`archived_at`) so bookings can keep referencing it.
  class Resource < ApplicationRecord
    include BranchInCompany

    KINDS = %w[chair room equipment].freeze
    MAX_NAME_LENGTH = 120
    # What a client may write; the audit trail records these plus `archived_at`.
    EDITABLE = %w[name kind active].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    before_validation :normalize_fields

    validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
    validates :kind, inclusion: { in: KINDS }
    validates :active, inclusion: { in: [ true, false ] }
    validate :branch_in_company

    # What management lists: everything not archived, paused resources included.
    scope :unarchived, -> { where(archived_at: nil) }
    # What can be offered for booking: not archived and not paused.
    scope :active, -> { unarchived.where(active: true) }

    def archived? = !archived_at.nil?

    private

    def normalize_fields
      self.name = name.strip if name
    end
  end
end
