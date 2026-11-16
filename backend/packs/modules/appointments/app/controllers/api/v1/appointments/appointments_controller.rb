module Api
  module V1
    module Appointments
      # Books an appointment from the panel at the route's branch. A concrete professional only: `any` is passed on so the use case
      # answers 422. Inside this namespace `Appointments` is Api::V1::Appointments: the pack's own constants are always written
      # `::Appointments`.
      class AppointmentsController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule
        include BranchOwner
        include ::Appointments::RequestParams

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so it would skip the check
        # for a principal whose access was revoked. A denied request never reaches the key either.
        before_action :authorize_booking, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: true

        def create
          attributes = booking_params
          appointment = ::Appointments::Book.call(
            company: Current.context.company, branch: Current.context.branch, customer_id: attributes[:customer_id],
            services: ::Appointments::Service.where(company_id:).in_order(attributes[:service_ids]),
            professional: ::Appointments::Availability::ProfessionalChoice.resolve(attributes[:professional_id], within: assigned_professionals),
            starts_at: attributes[:starts_at], notes: attributes[:notes], source: "panel"
          )
          render json: { data: ::Appointments::AppointmentSerializer.new(appointment).serializable_hash }, status: :created
        end

        private

        def authorize_booking
          authorize Current.context.branch, :create?, policy_class: ::Appointments::AppointmentPolicy
        end

        def booking_params
          values = typed_params(customer_id: String, professional_id: String, starts_at: String, notes: String)
          %i[customer_id professional_id starts_at].each { |name| raise ActionController::ParameterMissing, name if values[name].blank? }
          { customer_id: uuid(values[:customer_id], :customer_id), professional_id: professional_param(values[:professional_id]),
            starts_at: instant(values[:starts_at], :starts_at), notes: values[:notes], service_ids: service_ids }
        end

        # `typed_params` rejects arrays, so the list is read here.
        def service_ids
          raw = request.request_parameters["service_ids"]
          raise ActionController::ParameterMissing, :service_ids if raw.blank?
          raise ActionController::BadRequest, "service_ids must be a list of UUIDs" unless raw.is_a?(Array)

          uuid_list(raw, :service_ids)
        end

        def company_id = Current.context.company.id
      end
    end
  end
end
