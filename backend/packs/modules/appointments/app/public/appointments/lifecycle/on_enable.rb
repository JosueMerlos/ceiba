module Appointments
  module Lifecycle
    # Module hook run by Modules::Enable inside its transaction and the company's tenancy context (it opens none of its
    # own). On the FIRST activation only, gives every branch of the company that has no opening hours yet the default week,
    # Monday to Saturday from 08:00 to 18:00, so a company that just got the module has something to book against.
    #
    # A re-activation does nothing: "no hours" then may be a branch closed on purpose, which must stay closed. Only the
    # branches that exist NOW are covered: one added later starts without hours, which the availability rules read as closed
    # until someone configures it.
    module OnEnable
      DEFAULT_WEEKDAYS = (1..6).freeze
      DEFAULT_OPENS = "08:00".freeze
      DEFAULT_CLOSES = "18:00".freeze

      module_function

      def call(company:, first_activation:)
        return unless first_activation

        with_hours = WeeklySchedule.where(company_id: company.id, owner_type: "branch").distinct.pluck(:branch_id)
        Tenancy::Directory.branches.where(company_id: company.id).where.not(id: with_hours).order(:id).each { give_default_hours(it) }
      end

      def give_default_hours(branch)
        slots = DEFAULT_WEEKDAYS.map { { weekday: it, starts_at_local: DEFAULT_OPENS, ends_at_local: DEFAULT_CLOSES } }
        Staff::ReplaceSchedule.call(owner: branch, branch_id: branch.id, slots:, action: "schedule.defaults_created")
      end
      private_class_method :give_default_hours
    end
  end
end
