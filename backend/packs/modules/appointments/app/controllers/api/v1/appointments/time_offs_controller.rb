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
          authorize owner, :index?, policy_class: ::Appointments::TimeOffPolicy
          render_page(owner_time_offs, serializer: ::Appointments::TimeOffSerializer)
        end

        def create
          time_off = ::Appointments::Staff::CreateTimeOff.call(owner:, attributes: time_off_params)
          render json: { data: ::Appointments::TimeOffSerializer.new(time_off).serializable_hash }, status: :created
        end

        def destroy
          time_off = owner_time_offs.find(params[:"#{owner_kind}_time_off_id"])
          authorize owner, :destroy?, policy_class: ::Appointments::TimeOffPolicy
          ::Appointments::Staff::DeleteTimeOff.call(time_off:)
          head :no_content
        end

        private

        def authorize_creation = authorize(owner, :create?, policy_class: ::Appointments::TimeOffPolicy)

        def owner_time_offs = ::Appointments::TimeOff.where(company_id:).owned_by(owner)

        def time_off_params = typed_params(starts_at: String, ends_at: String, reason: String)
      end
    end
  end
end
