module Appointments
  # An absence of a professional or of a resource: an exact UTC interval. TENANT table. Overlapping absences of the same
  # owner are allowed (availability subtracts their union). `reason` is free text that may be private, so it is filtered from
  # logs and never audited.
  class TimeOff < ApplicationRecord
    include OwnerScoped

    OWNER_TYPES = %w[professional resource].freeze
    MAX_REASON_LENGTH = 200
    MAX_DURATION = 366.days
    # Years the database and the calendar can both represent sanely; anything else is a typo, not an absence.
    VALID_YEARS = (2000..2100)
    # Strict ISO-8601 date-time with an explicit offset: anything looser is read by Rails as UTC or as another instant.
    ISO_WITH_OFFSET = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})\z/
    # What a client may write; the owner comes from the route.
    EDITABLE = %w[starts_at ends_at reason].freeze

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Half-open: an absence that ends exactly at `from`, or starts exactly at `to`, does not overlap.
    scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }

    validates :owner_type, inclusion: { in: OWNER_TYPES }
    validates :starts_at, :ends_at, presence: true
    validates :reason, length: { maximum: MAX_REASON_LENGTH }, allow_nil: true
    validate :owner_columns_match_type
    validate :owner_in_company
    validate :timestamps_are_strict
    validate :interval_is_valid

    def starts_at=(value)
      typed_timestamps[:starts_at] = value
      super
    end

    def ends_at=(value)
      typed_timestamps[:ends_at] = value
      super
    end

    private

    # What the client typed, before the cast: a string must be a full ISO-8601 instant with its offset. The time-zone-aware
    # attribute casts at assignment and keeps no raw value, so the writers remember it.
    def typed_timestamps = (@typed_timestamps ||= {})

    def timestamps_are_strict
      %i[starts_at ends_at].each do |attribute|
        raw = typed_timestamps[attribute]
        errors.add(attribute, :invalid) if raw.is_a?(String) && !(ISO_WITH_OFFSET.match?(raw) && parseable?(raw))
      end
    end

    def parseable?(raw)
      Time.iso8601(raw)
      true
    rescue ArgumentError
      false
    end

    # The cast turns "infinity" into a Float, which has no calendar year.
    def in_valid_years?(value) = value.respond_to?(:utc) && VALID_YEARS.cover?(value.utc.year)

    def interval_is_valid
      %i[starts_at ends_at].each { errors.add(it, :invalid) if self[it] && errors[it].empty? && !in_valid_years?(self[it]) }
      return if starts_at.nil? || ends_at.nil? || errors.any?

      errors.add(:ends_at, :invalid) unless starts_at < ends_at && ends_at - starts_at <= MAX_DURATION
    end
  end
end
