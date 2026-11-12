module Appointments
  module Availability
    # Pure orchestration of the availability core. A professional is open where the branch and their own hours meet, minus
    # their absences and blocking appointments; a resource is open on the branch hours (narrowed by its own, when it has
    # any), minus its absences and occupation. A start is offered when the whole block (buffers included) fits in the
    # professional's free time and, if a resource kind is required, in some resource's of that kind. Everything comes in as values and goes
    # out as UTC slots, each start once and ordered.
    #
    # professionals: [{ id:, slots:, time_offs:, busy: }]; resources: [{ id:, kind:, slots:, time_offs:, busy: }];
    # load_by_day: { professional_id => { Date => blocking appointments } } (what LeastBusy balances on); plan: a ServicePlan.
    module Calculator
      module_function

      def call(branch_slots:, professionals:, resources:, plan:, load_by_day:, time_zone:, from_date:, to_date:, step_minutes:,
               now:, min_lead_minutes:, max_advance_days:)
        finder = lambda do |free|
          SlotFinder.call(free:, duration_minutes: plan.duration_minutes, buffer_before_minutes: plan.buffer_before_minutes,
                          buffer_after_minutes: plan.buffer_after_minutes, step_minutes:, time_zone:, now:, min_lead_minutes:, max_advance_days:)
        end
        expand = ->(slots) { WeeklyExpander.call(slots:, time_zone:, from_date:, to_date:) }
        branch_open = expand.call(branch_slots)

        by_professional = professionals.to_h { |person| [ person[:id], starts_by_epoch(finder, free_time(branch_open.intersect(expand.call(person[:slots])), person)) ] }
        by_resource = resources.select { it[:kind] == plan.required_kind }.to_h do |resource|
          open = resource[:slots].empty? ? branch_open : branch_open.intersect(expand.call(resource[:slots]))
          [ resource[:id], starts_by_epoch(finder, free_time(open, resource)) ]
        end

        assign(by_professional, by_resource, required: !plan.required_kind.nil?, load_by_day:, zone: TZInfo::Timezone.get(time_zone))
      end

      def free_time(open, owner) = open.subtract(IntervalSet.new(owner[:time_offs])).subtract(IntervalSet.new(owner[:busy]))

      # { epoch seconds of the start => slot span }.
      def starts_by_epoch(finder, free) = finder.call(free).index_by { it.starts_at.to_i }

      def assign(by_professional, by_resource, required:, load_by_day:, zone:)
        epochs = by_professional.values.flat_map(&:keys).uniq.sort
        epochs.filter_map do |epoch|
          resource_id = by_resource.select { |_, starts| starts.key?(epoch) }.keys.min
          next if required && resource_id.nil?

          free_ids = by_professional.select { |_, starts| starts.key?(epoch) }.keys
          day = zone.utc_to_local(Time.at(epoch).utc).to_date
          chosen = LeastBusy.call(candidates: free_ids, load_by_day:, day:)
          span = by_professional.fetch(chosen).fetch(epoch)
          Slot.new(starts_at: span.starts_at, ends_at: span.ends_at, professional_id: chosen, resource_id:)
        end
      end
      private_class_method :free_time, :starts_by_epoch, :assign
    end
  end
end
