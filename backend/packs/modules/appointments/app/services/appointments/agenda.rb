module Appointments
  # The appointments of one branch between two LOCAL dates of the branch (both included), in every status, for the agenda: ordered
  # by start, with their service lines, in a fixed number of queries whatever their number. Not paginated, because the agenda needs
  # the whole range: the range is capped, and one that holds more than LIMIT appointments is refused instead of cut short. `scope`
  # is what the principal may read (the policy scope). Must run inside a tenant context.
  class Agenda
    MAX_DAYS = 31
    LIMIT = 1000

    # The range itself is wrong.
    class InvalidRequest < FieldErrors; end

    def self.call(...) = new(...).call

    def initialize(scope:, branch:, from_date:, to_date:, professional_id: nil)
      @scope = scope
      @branch = branch
      @from_date = from_date
      @to_date = to_date
      @professional_id = professional_id
    end

    def call
      validate_range!
      appointments = filtered.order(:starts_at, :id).limit(LIMIT + 1).to_a
      raise InvalidRequest, [ { field: :to, code: :too_many_appointments } ] if appointments.size > LIMIT

      preload_lines(appointments)
      appointments
    end

    private

    def validate_range!
      raise InvalidRequest, [ { field: :to, code: :before_from } ] if @to_date < @from_date
      raise InvalidRequest, [ { field: :to, code: :too_far } ] if (@to_date - @from_date).to_i >= MAX_DAYS
    end

    def filtered
      zone = ActiveSupport::TimeZone[@branch.time_zone]
      # Local midnights; a midnight that does not exist (a DST jump at 00:00) becomes the first instant of that day.
      from = @from_date.in_time_zone(zone)
      to = (@to_date + 1).in_time_zone(zone)
      appointments = @scope.where(branch_id: @branch.id, starts_at: from...to)
      @professional_id ? appointments.where(professional_id: @professional_id) : appointments
    end

    # The lines filtered by company too, so the lookup uses the (organization, company, appointment) index.
    def preload_lines(appointments)
      ActiveRecord::Associations::Preloader.new(records: appointments, associations: :services_snapshot,
                                                scope: AppointmentService.where(company_id: @branch.company_id)).call
    end
  end
end
