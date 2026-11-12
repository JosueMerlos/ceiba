module Api
  module V1
    module Appointments
      # Free slots of one or several services (in sequence) with a professional or with any, at the route's branch. Order matters: the permission is asked FIRST (a role
      # without it never learns whether an id exists), then the query is checked for presence and shape, and only then are the
      # professional (among those assigned to the branch, unless `any`) and the services (among the company's) searched. Inside this namespace
      # `Appointments` is Api::V1::Appointments: the pack's own constants are always written `::Appointments`.
      class AvailabilityController < ::Api::BaseController
        include ::Modules::RequiresModule
        include BranchOwner
        include ::Appointments::AvailabilityQuery

        requires_module :appointments

        def show
          authorize Current.context.branch, :show?, policy_class: ::Appointments::AvailabilityPolicy
          query = availability_query
          services = services_in_order(company_services, query[:service_ids])
          professional = query[:professional_id] == :any ? :any : assigned_professionals.find(query[:professional_id])
          result = ::Appointments::Availability.call(company: Current.context.company, branch: Current.context.branch, services:, professional:,
                                                     from_date: query[:from], to_date: query[:to])
          render json: ::Appointments::AvailabilityResponse.call(result, time_zone: Current.context.branch.time_zone)
        end

        private

        def company_services = ::Appointments::Service.where(company_id:)
      end
    end
  end
end
