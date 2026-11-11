module Api
  module V1
    module Appointments
      # Weekly hours of the route's branch, of a professional assigned to it or of one of its resources (see BranchOwner). GET
      # lists the owner's slots in THIS branch; PUT replaces all of them at once.
      class SchedulesController < ::Api::BaseController
        include ::Modules::RequiresModule
        include BranchOwner

        requires_module :appointments

        MAX_SLOTS = 100
        SLOT_KEYS = %w[weekday starts_at_local ends_at_local].freeze
        private_constant :MAX_SLOTS, :SLOT_KEYS

        def show
          authorize probe, :show?, policy_class: ::Appointments::SchedulePolicy
          render_slots(branch_slots)
        end

        def update
          authorize probe, :update?, policy_class: ::Appointments::SchedulePolicy
          render_slots(::Appointments::Staff::ReplaceSchedule.call(owner:, branch_id:, slots: slots_param))
        end

        private

        # Describes the owner to the policy: no row is read or written through it.
        def probe
          schedule = ::Appointments::WeeklySchedule.new(owner_type: owner_kind, company_id:, branch_id:)
          schedule.professional = owner if owner_kind == "professional"
          schedule
        end

        def branch_slots = ::Appointments::WeeklySchedule.where(branch_id:, **owner_columns).order(:weekday, :starts_at_local)

        def render_slots(slots) = render json: { data: ::Appointments::WeeklyScheduleSerializer.new(slots).serializable_hash }

        # Required, and every slot an object of exactly the three fields with the right types: typed_params only checks the container.
        def slots_param
          slots = typed_params(slots: Array)[:slots]
          raise ActionController::BadRequest, "slots es obligatorio y debe ser una lista" if slots.nil?
          raise ActionController::BadRequest, "slots admite hasta #{MAX_SLOTS} franjas" if slots.size > MAX_SLOTS
          raise ActionController::BadRequest, "cada franja lleva weekday (entero) y starts_at_local y ends_at_local (texto HH:MM)" unless slots.all? { well_formed?(it) }

          slots
        end

        def well_formed?(slot)
          slot.is_a?(Hash) && slot.keys.sort == SLOT_KEYS.sort && slot["weekday"].is_a?(Integer) &&
            %w[starts_at_local ends_at_local].all? { slot[it].is_a?(String) && slot[it].length <= 16 && !slot[it].include?("\u0000") }
        end
      end
    end
  end
end
