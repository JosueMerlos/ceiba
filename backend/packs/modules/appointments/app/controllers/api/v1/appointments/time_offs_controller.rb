module Api
  module V1
    module Appointments
      # Absences of a professional assigned to the route's branch or of one of its resources (see BranchOwner). The absence is
      # searched ONLY among the route owner's: another owner's id is a 404 and is never deleted through somebody else's URL.
      class TimeOffsController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule
        include BranchOwner

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        def index
          authorize probe, :index?, policy_class: ::Appointments::TimeOffPolicy
          render_page(owner_time_offs, serializer: ::Appointments::TimeOffSerializer)
        end

        def create
          time_off = ::Appointments::Staff::CreateTimeOff.call(owner:, attributes: time_off_params)
          render json: { data: ::Appointments::TimeOffSerializer.new(time_off).serializable_hash }, status: :created
        end

        def destroy
          time_off = owner_time_offs.find(params[:"#{owner_kind}_time_off_id"])
          authorize time_off, :destroy?, policy_class: ::Appointments::TimeOffPolicy
          ::Appointments::Staff::DeleteTimeOff.call(time_off:)
          head :no_content
        end

        private

        def authorize_creation = authorize(probe, :create?, policy_class: ::Appointments::TimeOffPolicy)

        # Describes the owner to the policy: no row is read or written through it.
        def probe
          time_off = ::Appointments::TimeOff.new(owner_type: owner_kind, company_id:)
          time_off.professional = owner if owner_kind == "professional"
          time_off
        end

        def owner_time_offs = ::Appointments::TimeOff.where(company_id:, **owner_columns)

        def time_off_params = typed_params(starts_at: String, ends_at: String, reason: String)
      end
    end
  end
end
