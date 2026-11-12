module Appointments
  # Free slots for one or several services at a branch, with one professional or with any of them (`:any`), over a range of the
  # branch's local dates (inclusive). Returns a Result: the slots (UTC, each with the professional and the resource assigned) plus
  # the duration, buffers, price and grid step they were computed with. Eligibility is checked first and reported all at once
  # through InvalidRequest; the data is then loaded with a fixed number of queries and handed to the pure calculator. Must run
  # inside a tenant context.
  module Availability
    MAX_RANGE_DAYS = 31
    MAX_SERVICES = 5

    Result = Data.define(:slots, :duration_minutes, :buffer_before_minutes, :buffer_after_minutes, :price_minor, :currency, :step_minutes)

    module_function

    # `services` is the ordered list of Service records asked for; `professional` is a Professional or :any.
    def call(company:, branch:, services:, professional:, from_date:, to_date:, now: Time.current)
      requirements = ensure_eligible!(company:, branch:, services:, professional:, from_date:, to_date:, now:)
      loaded = DataLoader.call(company:, branch:, services:, professional:, from_date:, to_date:, requirements:)
      slots = Calculator.call(**loaded.to_h, time_zone: branch.time_zone, from_date:, to_date:, now:)
      plan = loaded.plan
      Result.new(slots:, duration_minutes: plan.duration_minutes, buffer_before_minutes: plan.buffer_before_minutes,
                 buffer_after_minutes: plan.buffer_after_minutes, price_minor: plan.price_minor, currency: plan.currency, step_minutes: loaded.step_minutes)
    end

    # Shared eligibility check for non-HTTP callers such as booking. Raises InvalidRequest with every reason the request
    # cannot be answered. Returns the [[service_id, kind]] resource requirements it read, so the loader does not read them again.
    def ensure_eligible!(company:, branch:, services:, professional:, from_date:, to_date:, now: Time.current)
      foreign = company_errors(company, branch:, services:, professional:)
      raise InvalidRequest, foreign if foreign.any?

      requirements = requirement_rows(company, services)
      errors = branch_errors(branch) + professional_errors(company, branch, professional) +
               service_errors(company, services, professional, requirements) + range_errors(branch, from_date, to_date, now)
      raise InvalidRequest, errors if errors.any?

      requirements
    end

    # Everything the request names must belong to the company asked about; a mismatch is reported alone (once per field) so
    # nothing else about the foreign records is looked up.
    def company_errors(company, branch:, services:, professional:)
      named = { branch_id: [ branch ], service_ids: services, professional_id: professional == :any ? [] : [ professional ] }
      named.filter_map do |field, records|
        { field:, code: :wrong_company } if records.any? { it.company_id != company.id }
      end
    end

    # A closed branch offers nothing, whatever its hours say.
    def branch_errors(branch) = branch.inactive? ? [ { field: :branch_id, code: :inactive } ] : []

    def professional_errors(company, branch, professional)
      return [] if professional == :any

      errors = []
      errors << { field: :professional_id, code: :inactive } if professional.archived? || !professional.active
      # Guards callers that do not resolve the professional through the branch.
      errors << { field: :professional_id, code: :not_assigned } unless ProfessionalBranchAssignment.exists?(company_id: company.id, professional_id: professional.id, branch_id: branch.id)
      errors
    end

    # Each check is one grouped query whatever the number of services. With `:any` nobody is required to provide them: the
    # eligible professionals are simply the ones who do, possibly none.
    def service_errors(company, services, professional, requirements)
      return [ { field: :service_ids, code: :blank } ] if services.empty?

      ids = services.map(&:id)
      codes = []
      codes << :too_many if services.size > MAX_SERVICES
      codes << :duplicated if ids.uniq.size != ids.size
      codes << :inactive if services.any? { it.archived? || !it.active }
      codes << :not_provided if professional != :any && !provides_all?(company, professional, ids.uniq)
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

    def range_errors(branch, from_date, to_date, now)
      errors = []
      errors << { field: :from, code: :too_early } if from_date < now.in_time_zone(branch.time_zone).to_date - 1
      errors << { field: :to, code: :invalid_range } unless from_date <= to_date && (to_date - from_date).to_i < MAX_RANGE_DAYS
      errors
    end

    private_class_method :company_errors, :branch_errors, :professional_errors, :service_errors, :requirement_rows, :provides_all?, :range_errors
  end
end
