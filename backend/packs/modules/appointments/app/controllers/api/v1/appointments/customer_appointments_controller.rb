module Api
  module V1
    module Appointments
      # A customer's appointment history at the route's branch, for the customer profile. Only the branch's appointments: what
      # happened at other branches belongs to whoever acts from them. An archived customer keeps their history.
      class CustomerAppointmentsController < ::Api::BaseController
        include ::Modules::RequiresModule

        requires_module :appointments

        def index
          authorize Current.context.branch, :customer_history?, policy_class: ::Appointments::AppointmentPolicy
          raise ActiveRecord::RecordNotFound unless ::Customers::Lookup.exists_id?(id: params[:customer_id], company: Current.context.company)

          page = ::Api::Pagination::Cursor.paginate(history, limit: params[:limit], after: params[:after], order: { starts_at: :desc })
          render json: { data: serialize(page.records), page: page.meta }
        end

        private

        def history
          ::Appointments::Appointment.where(company_id: Current.context.company.id, branch_id: Current.context.branch.id, customer_id: params[:customer_id])
                                     .includes(:services_snapshot)
        end

        def serialize(appointments)
          service_ids = appointments.flat_map { it.services_snapshot.map(&:service_id) }.uniq
          names = {
            professional_names: ::Appointments::Professional.where(id: appointments.map(&:professional_id).uniq).pluck(:id, :display_name).to_h,
            service_names: ::Appointments::Service.where(id: service_ids).pluck(:id, :name).to_h
          }
          ::Appointments::CustomerAppointmentSerializer.new(appointments, params: names).serializable_hash
        end
      end
    end
  end
end
