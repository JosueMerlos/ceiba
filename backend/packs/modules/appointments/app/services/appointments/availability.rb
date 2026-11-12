module Appointments
  # Free slots of one professional for one service at a branch, over a range of the branch's local dates (inclusive). Returns
  # a Result: the UTC intervals of the service's effective duration plus the duration and grid step they were computed with.
  # Eligibility is checked first and reported all at once through InvalidRequest; the data is then loaded with a fixed number
  # of queries and handed to the pure calculator. Must run inside a tenant context.
  module Availability
    MAX_RANGE_DAYS = 31

    Result = Data.define(:slots, :duration_minutes, :step_minutes)

    module_function

    def call(company:, branch:, service:, professional:, from_date:, to_date:, now: Time.current)
      ensure_eligible!(branch:, service:, professional:, from_date:, to_date:, now:)
      loaded = DataLoader.call(company:, branch:, service:, professional:, from_date:, to_date:)
      slots = Calculator.call(**loaded.to_h, time_zone: branch.time_zone, from_date:, to_date:, now:)
      Result.new(slots:, duration_minutes: loaded.duration_minutes, step_minutes: loaded.step_minutes)
    end

    # Shared eligibility check for non-HTTP callers such as booking. Raises InvalidRequest with every reason the request
    # cannot be answered.
    def ensure_eligible!(branch:, service:, professional:, from_date:, to_date:, now: Time.current)
      errors = branch_errors(branch) + professional_errors(branch, professional) + service_errors(service, professional) + range_errors(branch, from_date, to_date, now)
      raise InvalidRequest, errors if errors.any?
    end

    # A closed branch offers nothing, whatever its hours say.
    def branch_errors(branch) = branch.inactive? ? [ { field: :branch_id, code: :inactive } ] : []

    def professional_errors(branch, professional)
      errors = []
      errors << { field: :professional_id, code: :inactive } if professional.archived? || !professional.active
      # Guards callers that do not resolve the professional through the branch.
      errors << { field: :professional_id, code: :not_assigned } unless ProfessionalBranchAssignment.exists?(professional_id: professional.id, branch_id: branch.id)
      errors
    end

    def service_errors(service, professional)
      errors = []
      errors << { field: :service_id, code: :inactive } if service.archived? || !service.active
      errors << { field: :service_id, code: :not_provided } unless ProfessionalService.exists?(professional_id: professional.id, service_id: service.id)
      errors
    end

    def range_errors(branch, from_date, to_date, now)
      errors = []
      errors << { field: :from, code: :too_early } if from_date < now.in_time_zone(branch.time_zone).to_date - 1
      errors << { field: :to, code: :invalid_range } unless from_date <= to_date && (to_date - from_date).to_i < MAX_RANGE_DAYS
      errors
    end

    private_class_method :branch_errors, :professional_errors, :service_errors, :range_errors
  end
end
