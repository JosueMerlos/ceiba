module Appointments
  # Free slots for one or several services at a branch, with one professional or with any of them (a ProfessionalChoice), over a
  # range of the branch's local dates (inclusive). Returns a Result: the slots (UTC, each with the professional and the resource
  # assigned), the ServicePlan (duration, buffers, price) and the grid step they were computed with. Eligibility is checked first
  # and reported all at once through InvalidRequest; the data is then loaded with a fixed number of queries and handed to the pure
  # calculator. Must run inside a tenant context.
  module Availability
    MAX_RANGE_DAYS = 31
    MAX_SERVICES = 5

    Result = Data.define(:slots, :plan, :step_minutes)

    # The outcome of a passed eligibility check: the [[service_id, kind]] resource requirements it read (so the loader does not read
    # them again) and the one resource kind the visit needs, nil when none. A caller that already checked hands it back to `call`.
    Eligibility = Data.define(:requirements) do
      def required_kind = requirements.first&.last
    end

    # Whose rules the booking window follows. A customer books within the lead time and advance days the branch sets; staff
    # (the panel) may book sooner or further ahead. Either way a block never starts before `now`.
    BOOKING_WINDOWS = %i[customer staff].freeze

    module_function

    # `services` is the ordered list of Service records asked for. `max_range_days` is the longest range the caller serves.
    # `booking_window` is :customer (the branch's lead time and advance limit) or :staff (neither; hours, absences and the grid still apply).
    # `eligibility` is the result of an `ensure_eligible!` the caller already ran for this same request; without it, it is run here.
    def call(company:, branch:, services:, professional:, from_date:, to_date:, max_range_days: MAX_RANGE_DAYS, now: Time.current, booking_window: :customer,
             eligibility: nil)
      raise ArgumentError, "booking_window must be one of #{BOOKING_WINDOWS.inspect}, got #{booking_window.inspect}" unless BOOKING_WINDOWS.include?(booking_window)

      eligibility ||= ensure_eligible!(company:, branch:, services:, professional:, from_date:, to_date:, max_range_days:, now:)
      loaded = DataLoader.call(company:, branch:, services:, professional:, from_date:, to_date:, requirements: eligibility.requirements, booking_window:)
      slots = Calculator.call(**loaded.to_h, time_zone: branch.time_zone, from_date:, to_date:, now:)
      Result.new(slots:, plan: loaded.plan, step_minutes: loaded.step_minutes)
    end

    # Shared eligibility check for non-HTTP callers such as booking. Raises InvalidRequest with every reason the request
    # cannot be answered. Returns an Eligibility.
    def ensure_eligible!(company:, branch:, services:, professional:, from_date:, to_date:, max_range_days: MAX_RANGE_DAYS, now: Time.current)
      foreign = company_errors(company, branch:, services:, professional:)
      raise InvalidRequest, foreign if foreign.any?

      requirements = requirement_rows(company, services)
      errors = branch_errors(branch) + professional_errors(company, branch, professional) +
               service_errors(company, services, professional, requirements) + range_errors(branch, from_date, to_date, max_range_days, now)
      raise InvalidRequest, errors if errors.any?

      Eligibility.new(requirements:)
    end

    # Everything the request names must belong to the company asked about; a mismatch is reported alone (once per field) so
    # nothing else about the foreign records is looked up.
    def company_errors(company, branch:, services:, professional:)
      named = { branch_id: [ branch ], service_ids: services, professional_id: professional.named }
      named.filter_map do |field, records|
        { field:, code: :wrong_company } if records.any? { it.company_id != company.id }
      end
    end

    # A closed branch offers nothing, whatever its hours say.
    def branch_errors(branch) = branch.inactive? ? [ { field: :branch_id, code: :inactive } ] : []

    def professional_errors(company, branch, professional)
      return [] if professional.any?

      person = professional.professional
      errors = []
      errors << { field: :professional_id, code: :inactive } if person.archived? || !person.active
      # Guards callers that do not resolve the professional through the branch.
      errors << { field: :professional_id, code: :not_assigned } unless Professional.assigned_to(branch).exists?(person.id)
      errors
    end

    # Each check is one grouped query whatever the number of services. With any nobody is required to provide them: the
    # eligible professionals are simply the ones who do, possibly none.
    def service_errors(company, services, professional, requirements)
      return [ { field: :service_ids, code: :blank } ] if services.empty?

      ids = services.map(&:id)
      codes = []
      codes << :too_many if services.size > MAX_SERVICES
      codes << :duplicated if ids.uniq.size != ids.size
      codes << :inactive if services.any? { it.archived? || !it.active }
      codes << :not_provided if !professional.any? && !provides_all?(company, professional.professional, ids.uniq)
      codes << :multiple_resource_kinds if requirements.map(&:last).uniq.size > 1
      codes.map { { field: :service_ids, code: it } }
    end

    def requirement_rows(company, services)
      return [] if services.empty?

      ServiceResourceRequirement.where(company_id: company.id, service_id: services.map(&:id)).pluck(:service_id, :kind)
    end

    def provides_all?(company, professional, ids)
      ProfessionalService.where(company_id: company.id, professional_id: professional.id, service_id: ids).distinct.count(:service_id) == ids.size
    end

    def range_errors(branch, from_date, to_date, max_range_days, now)
      errors = []
      errors << { field: :from, code: :too_early } if from_date < now.in_time_zone(branch.time_zone).to_date - 1
      errors << { field: :to, code: :invalid_range } unless from_date <= to_date && (to_date - from_date).to_i < max_range_days
      errors
    end

    private_class_method :company_errors, :branch_errors, :professional_errors, :service_errors, :requirement_rows, :provides_all?, :range_errors
  end
end
