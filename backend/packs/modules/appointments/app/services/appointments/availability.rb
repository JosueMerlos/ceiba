module Appointments
  # Free slots of one professional for one service at a branch, over a range of the branch's local dates (inclusive). Returns
  # UTC intervals of the service's effective duration. Eligibility is checked first and reported all at once through
  # InvalidRequest; the data is then loaded with a fixed number of queries and handed to the pure calculator. Must run inside
  # a tenant context.
  module Availability
    MAX_RANGE_DAYS = 31

    module_function

    def call(company:, branch:, service:, professional:, from_date:, to_date:, now: Time.current)
      ensure_eligible!(branch:, service:, professional:, from_date:, to_date:)
      loaded = DataLoader.call(company:, branch:, service:, professional:, from_date:, to_date:)
      settings = loaded.settings

      Calculator.call(branch_slots: loaded.branch_slots, professional_slots: loaded.professional_slots, time_offs: loaded.time_offs,
                      busy: loaded.busy, time_zone: branch.time_zone, from_date:, to_date:, duration_minutes: loaded.duration_minutes,
                      step_minutes: settings.fetch("slot_step_minutes"), now:, min_lead_minutes: settings.fetch("min_lead_time_minutes"),
                      max_advance_days: settings.fetch("max_advance_days"))
    end

    # Raises InvalidRequest with every reason the request cannot be answered.
    def ensure_eligible!(branch:, service:, professional:, from_date:, to_date:)
      errors = professional_errors(branch, professional) + service_errors(service, professional) + range_errors(from_date, to_date)
      raise InvalidRequest, errors if errors.any?
    end

    def professional_errors(branch, professional)
      errors = []
      errors << { field: :professional_id, code: :inactive } if professional.archived? || !professional.active
      errors << { field: :professional_id, code: :not_assigned } unless ProfessionalBranchAssignment.exists?(professional_id: professional.id, branch_id: branch.id)
      errors
    end

    def service_errors(service, professional)
      errors = []
      errors << { field: :service_id, code: :inactive } if service.archived? || !service.active
      errors << { field: :service_id, code: :not_provided } unless ProfessionalService.exists?(professional_id: professional.id, service_id: service.id)
      errors
    end

    def range_errors(from_date, to_date)
      valid = from_date <= to_date && (to_date - from_date).to_i < MAX_RANGE_DAYS
      valid ? [] : [ { field: :to, code: :invalid_range } ]
    end

    private_class_method :professional_errors, :service_errors, :range_errors
  end
end
