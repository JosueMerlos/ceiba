module Api
  module V1
    module Appointments
      # What the appointment controllers share: the appointment a member route names, searched ONLY among the route branch's
      # (another branch's or company's is a 404), and its rendering.
      module BranchAppointment
        extend ActiveSupport::Concern

        private

        def appointment
          @appointment ||= ::Appointments::Appointment.where(company_id: Current.context.company.id, branch_id: Current.context.branch.id)
                                                      .find(params[:appointment_id])
        end

        def render_appointment(record, status: :ok, serializer: ::Appointments::AppointmentSerializer, params: {})
          render json: { data: serializer.new(record, params:).serializable_hash }, status:
        end
      end
    end
  end
end
