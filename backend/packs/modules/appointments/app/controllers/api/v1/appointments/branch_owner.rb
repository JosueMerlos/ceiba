module Api
  module V1
    module Appointments
      # What the schedule and absence controllers share: the owner a URL names. `owner_kind` is a ROUTE default (a client cannot
      # send it). The owner is searched among the ones that belong to the route's branch: a professional assigned to it (another
      # branch's, another company's or an unassigned one is a 404 for every role), a resource of the branch, or the branch itself.
      module BranchOwner
        extend ActiveSupport::Concern

        private

        def owner_kind = request.path_parameters.fetch(:owner_kind)

        def branch_id = Current.context.branch.id

        def company_id = Current.context.company.id

        def owner
          @owner ||= case owner_kind
          when "professional" then assigned_professionals.find(params[:professional_id])
          when "resource" then branch_resources.find(params[:resource_id])
          else Current.context.branch
          end
        end

        def assigned_professionals
          ::Appointments::Professional.where(company_id:, id: ::Appointments::ProfessionalBranchAssignment.where(branch_id:).select(:professional_id))
        end

        def branch_resources = ::Appointments::Resource.where(company_id:, branch_id:)
      end
    end
  end
end
