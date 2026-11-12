module Api
  module V1
    module Appointments
      # Free slots of a professional for a service at the route's branch. Order matters: the permission is asked FIRST (a role
      # without it never learns whether an id exists), then the query is checked for presence and shape, and only then are the
      # professional (among those assigned to the branch) and the service (among the company's) searched. Inside this namespace
      # `Appointments` is Api::V1::Appointments: the pack's own constants are always written `::Appointments`.
      class AvailabilityController < ::Api::BaseController
        include ::Modules::RequiresModule
        include BranchOwner

        requires_module :appointments

        QUERY_PARAMS = %w[service_id professional_id from to].freeze
        UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
        DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

        def show
          authorize Current.context.branch, :show?, policy_class: ::Appointments::AvailabilityPolicy
          query = availability_query
          service = company_services.find(query[:service_id])
          professional = assigned_professionals.find(query[:professional_id])
          result = ::Appointments::Availability.call(company: Current.context.company, branch: Current.context.branch, service:, professional:,
                                                     from_date: query[:from], to_date: query[:to])
          render json: { data: ::Appointments::AvailabilitySlotSerializer.new(result.slots).serializable_hash,
                         meta: { time_zone: Current.context.branch.time_zone, duration_minutes: result.duration_minutes, step_minutes: result.step_minutes } }
        end

        private

        def company_services = ::Appointments::Service.where(company_id:)

        # A missing parameter is a 400 `request.invalid`; one that is not the shape asked for is a 400 `request.bad_request`.
        # `typed_params` only reads the body, so the query is parsed here.
        def availability_query
          reject_repeated_query_params
          values = %i[service_id professional_id from to].index_with { required_query_param(it) }
          { service_id: uuid(values[:service_id], :service_id), professional_id: uuid(values[:professional_id], :professional_id),
            from: date(values[:from], :from), to: date(values[:to], :to) }
        end

        # Rack keeps the last value of a repeated parameter and the rest vanish silently; the raw query string still shows them.
        def reject_repeated_query_params
          raw = Rack::Utils.parse_query(request.query_string)
          repeated = QUERY_PARAMS.find { raw[it].is_a?(Array) }
          raise ActionController::BadRequest, "#{repeated} must be a single value" if repeated
        end

        def required_query_param(name)
          value = params[name]
          raise ActionController::ParameterMissing, name if value.blank?
          raise ActionController::BadRequest, "#{name} must be a single value" unless value.is_a?(String)

          value
        end

        def uuid(value, name)
          raise ActionController::BadRequest, "#{name} must be a UUID" unless UUID_FORMAT.match?(value)

          value.downcase
        end

        def date(value, name)
          raise ActionController::BadRequest, "#{name} must be a date as YYYY-MM-DD" unless DATE_FORMAT.match?(value)

          Date.strptime(value, "%Y-%m-%d")
        rescue Date::Error
          raise ActionController::BadRequest, "#{name} must be a valid date as YYYY-MM-DD"
        end
      end
    end
  end
end
