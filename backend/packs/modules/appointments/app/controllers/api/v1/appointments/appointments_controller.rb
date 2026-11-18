module Api
  module V1
    module Appointments
      # The appointments of the route's branch: the agenda listing, booking from the panel, and one appointment's detail and notes.
      # Booking takes a concrete professional only: `any` is passed on so the use case answers 422. The appointment of a member route
      # is searched among the branch's (another branch's or company's is a 404). Inside this namespace `Appointments` is
      # Api::V1::Appointments: the pack's own constants are always written `::Appointments`.
      class AppointmentsController < ::Api::BaseController
        include ::Idempotency::Idempotent
        include ::Modules::RequiresModule
        include BranchOwner
        include BranchAppointment
        include ::Appointments::RequestParams

        AGENDA_PARAMS = %w[from to professional_id].freeze

        requires_module :appointments

        # Authorization runs OUTSIDE the idempotency filter: a replayed response never runs the action, so it would skip the check
        # for a principal whose access was revoked. A denied request never reaches the key either.
        before_action :authorize_booking, only: :create
        # Declared after Access::Authorization's around action: the idempotency key needs the tenancy context.
        idempotent :create, required: true

        # The permission is asked FIRST (a role without it never learns whether a professional exists), then the query is read.
        def index
          authorize Current.context.branch, :index?, policy_class: ::Appointments::AppointmentPolicy
          query = agenda_query
          readable = policy_scope(::Appointments::Appointment.where(company_id:), policy_scope_class: ::Appointments::AppointmentPolicy::Scope)
          appointments = ::Appointments::Agenda.call(scope: readable, branch: Current.context.branch, from_date: query[:from], to_date: query[:to],
                                                     professional_id: query[:professional_id])
          render json: { data: ::Appointments::AgendaAppointmentSerializer.new(appointments, params: { customer_names: customer_names(appointments) }).serializable_hash }
        end

        def show
          authorize appointment, :show?, policy_class: ::Appointments::AppointmentPolicy
          render_appointment(appointment, serializer: ::Appointments::AppointmentDetailSerializer)
        end

        def create
          attributes = booking_params
          booked = ::Appointments::Book.call(
            company: Current.context.company, branch: Current.context.branch, customer_id: attributes[:customer_id],
            services: ::Appointments::Service.where(company_id:).in_order(attributes[:service_ids]),
            professional: ::Appointments::Availability::ProfessionalChoice.resolve(attributes[:professional_id], within: assigned_professionals),
            starts_at: attributes[:starts_at], notes: attributes[:notes], source: "panel"
          )
          render_appointment(booked, status: :created)
        end

        # Notes only, under the version the client read.
        def update
          authorize appointment, :update?, policy_class: ::Appointments::AppointmentPolicy
          values = typed_params(notes: String, lock_version: Integer)
          raise ActionController::ParameterMissing, :lock_version if values[:lock_version].nil?
          # A body without the key must not clear the notes: only an explicit null does.
          raise ActionController::ParameterMissing, :notes unless request.request_parameters.key?("notes")

          ::Appointments::UpdateNotes.call(appointment:, notes: values[:notes], lock_version: values[:lock_version])
          render_appointment(appointment, serializer: ::Appointments::AppointmentDetailSerializer)
        end

        private

        def authorize_booking
          authorize Current.context.branch, :create?, policy_class: ::Appointments::AppointmentPolicy
        end

        def customer_names(appointments)
          return {} unless ::Appointments::AppointmentPolicy.new(Current.principal, Current.context.branch).customer_names?

          ::Customers::Lookup.full_names(ids: appointments.map(&:customer_id).uniq, company: Current.context.company)
        end

        def agenda_query
          reject_repeated_query_params(AGENDA_PARAMS)
          { from: date(required_query_param("from"), :from), to: date(required_query_param("to"), :to),
            professional_id: optional_query_param("professional_id")&.then { uuid(it, :professional_id) } }
        end

        def booking_params
          values = typed_params(customer_id: String, professional_id: String, starts_at: String, notes: String)
          %i[customer_id professional_id starts_at].each { |name| raise ActionController::ParameterMissing, name if values[name].blank? }
          { customer_id: uuid(values[:customer_id], :customer_id), professional_id: professional_param(values[:professional_id]),
            starts_at: instant(values[:starts_at], :starts_at), notes: values[:notes], service_ids: }
        end

        # `typed_params` rejects arrays, so the list is read here.
        def service_ids
          raw = request.request_parameters["service_ids"]
          raise ActionController::ParameterMissing, :service_ids if raw.blank?
          raise ActionController::BadRequest, "service_ids must be a list of UUIDs" unless raw.is_a?(Array)

          uuid_list(raw, :service_ids)
        end
      end
    end
  end
end
