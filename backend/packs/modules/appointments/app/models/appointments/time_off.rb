module Appointments
  # An absence of a professional or of a resource: an exact UTC interval. TENANT table. Overlapping absences of the same
  # owner are allowed (availability subtracts their union). `reason` is free text that may be private, so it is filtered from
  # logs and never audited.
  class TimeOff < ApplicationRecord
    include OwnerScoped

    OWNER_TYPES = %w[professional resource].freeze
    MAX_REASON_LENGTH = 200
    MAX_DURATION = 366.days
    # What a client may write; the owner comes from the route.
    EDITABLE = %w[starts_at ends_at reason].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    validates :owner_type, inclusion: { in: OWNER_TYPES }
    validates :starts_at, :ends_at, presence: true
    validates :reason, length: { maximum: MAX_REASON_LENGTH }, allow_nil: true
    validate :owner_columns_match_type
    validate :owner_in_company
    validate :interval_is_valid

    private

    def interval_is_valid
      return if starts_at.nil? || ends_at.nil?

      errors.add(:ends_at, :invalid) unless starts_at < ends_at && ends_at - starts_at <= MAX_DURATION
    end
  end
end
