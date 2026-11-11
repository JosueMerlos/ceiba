module Api
  module V1
    module Appointments
      # The service catalog of the route's company. Everything is searched inside that company, so a service of another
      # company is a 404, never a 403. Inside this namespace `Appointments` is Api::V1::Appointments: the pack's own
      # constants are always written `::Appointments`.
      class ServicesController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so authorizing in it
        # would fail verify_authorized and would skip the permission check for a principal whose access was revoked.
        before_action :authorize_creation, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: false

        # Active and paused services, not archived ones; `active` narrows to one state. Listed in creation order (the
        # pagination cursor is the id); `position` is there for the client to arrange them.
        def index
          authorize company_services, :index?, policy_class: ::Appointments::ServicePolicy
          services = policy_scope(company_services.unarchived, policy_scope_class: ::Appointments::ServicePolicy::Scope)
          services = services.where(active: active_filter) unless active_filter.nil?
          render_page(services, serializer: ::Appointments::ServiceSerializer)
        end

        def show
          service = company_services.find(params[:id])
          authorize service, :show?, policy_class: ::Appointments::ServicePolicy
          render_service(service)
        end

        def create
          service = ::Appointments::Catalog::CreateService.call(company_id:, attributes: service_params)
          render_service(service, status: :created)
        end

        def update
          service = company_services.find(params[:id])
          authorize service, :update?, policy_class: ::Appointments::ServicePolicy
          render_service(::Appointments::Catalog::UpdateService.call(service:, attributes: service_params))
        end

        def destroy
          service = company_services.find(params[:id])
          authorize service, :destroy?, policy_class: ::Appointments::ServicePolicy
          ::Appointments::Catalog::ArchiveService.call(service:)
          head :no_content
        end

        private

        def authorize_creation
          authorize ::Appointments::Service.new(company_id:), :create?, policy_class: ::Appointments::ServicePolicy
        end

        def company_id = Current.context.company.id

        def company_services = ::Appointments::Service.where(company_id:)

        # nil when absent; anything but "true" or "false" is a 400.
        def active_filter
          return @active_filter if defined?(@active_filter)

          raw = params[:active]
          raise ActionController::BadRequest, "active debe ser true o false" unless raw.nil? || %w[true false].include?(raw)

          @active_filter = raw.nil? ? nil : raw == "true"
        end

        def render_service(service, status: :ok)
          render json: { data: ::Appointments::ServiceSerializer.new(service).serializable_hash }, status:
        end

        def service_params
          typed_params(name: String, currency: String, duration_minutes: Integer, buffer_before_minutes: Integer,
                       buffer_after_minutes: Integer, price_minor: Integer, position: Integer, active: :boolean)
        end
      end
    end
  end
end
