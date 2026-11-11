module Appointments
  # One slot of weekly opening hours, in the branch's local wall-clock time, for a branch, a professional or a resource.
  # TENANT table. The database is the safety net (composite FKs for who may have hours where, three exclusion constraints
  # for overlaps, CHECKs); the model reports the same rules as field errors first. Slots are whole minutes and never cross
  # midnight.
  class WeeklySchedule < ApplicationRecord
    include OwnerScoped
    include BranchInCompany

    OWNER_TYPES = %w[branch professional resource].freeze
    WEEKDAYS = (0..6)

    acts_as_tenant :organization, class_name: "Tenancy::Organization"

    # Wall-clock values: converting them through the application's zone would shift the hour the user typed.
    self.skip_time_zone_conversion_for_attributes = %i[starts_at_local ends_at_local]

    validates :owner_type, inclusion: { in: OWNER_TYPES }
    validates :weekday, inclusion: { in: WEEKDAYS }
    validates :starts_at_local, :ends_at_local, presence: true
    validate :owner_columns_match_type
    validate :whole_minutes
    validate :ends_after_start
    validate :branch_in_company
    validate :owner_belongs_to_branch
    validate :no_overlap

    # "09:00": what the API shows; the clock part of the stored time.
    def self.clock(time) = time&.strftime("%H:%M")

    private

    def whole_minutes
      %i[starts_at_local ends_at_local].each do |attribute|
        time = self[attribute]
        errors.add(attribute, :invalid) if time && (time.sec != 0 || time.subsec != 0)
      end
    end

    def ends_after_start
      return if starts_at_local.nil? || ends_at_local.nil? || errors.any? { %i[starts_at_local ends_at_local].include?(it.attribute) }

      errors.add(:ends_at_local, :invalid) unless starts_at_local < ends_at_local
    end

    # A professional only has hours where they are assigned; a resource only in its own branch.
    def owner_belongs_to_branch
      if professional_owner? && professional_id.present? &&
         !(professional&.company_id == company_id && ProfessionalBranchAssignment.exists?(professional_id:, branch_id:))
        errors.add(:professional_id, :invalid)
      end
      errors.add(:resource_id, :invalid) if resource_owner? && resource_id.present? && !(resource&.company_id == company_id && resource.branch_id == branch_id)
    end

    # Same owner, same weekday, minute ranges that intersect ([start, end) like the exclusion constraints).
    def no_overlap
      return if errors.any?

      errors.add(:base, :overlap) if owner_slots.where.not(id:).exists?(
        [ "starts_at_local < ?::time AND ends_at_local > ?::time", ends_at_local.strftime("%H:%M"), starts_at_local.strftime("%H:%M") ]
      )
    end

    # A branch's slots are per branch; a professional's span all their branches (the exclusion constraint does too).
    def owner_slots
      slots = self.class.where(weekday:, owner_type:, professional_id:, resource_id:)
      branch_owner? ? slots.where(branch_id:) : slots
    end
  end
end
