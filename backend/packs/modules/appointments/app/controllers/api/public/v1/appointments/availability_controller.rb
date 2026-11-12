module Api
  module Public
    module V1
      module Appointments
        # Free slots for anyone, with no session: the booking page asks it by the company's slug. Inside this namespace
        # `Appointments` is Api::Public::V1::Appointments: the pack's own constants are always written `::Appointments`.
        #
        # Nothing here reveals what is closed. An unknown slug, the module off, booking disabled, another company's branch,
        # an inactive service or a professional that does not apply all answer the same 404; only a bad date range is a 422
        # (it says nothing about the company). Order: the company is opened from the slug and the module gate runs (both
        # before anything else), then the shape of the query, the doors, the lookups, the range and the use case.
        class AvailabilityController < ::Api::BaseController
          include ::Modules::RequiresModule
          include ::Appointments::AvailabilityQuery

          MAX_RANGE_DAYS = 14
          MAX_SERVICES = ::Appointments::Availability::MAX_SERVICES
          # The only use case errors that are told apart: they describe the dates asked for, never the company's data.
          VISIBLE_ERRORS = [ %i[to invalid_range], %i[from too_early] ].freeze

          skip_authentication!
          skip_authorization!(reason: "endpoint anónimo: no hay principal; solo expone huecos libres, sin datos personales, de una empresa con la reserva pública activa", only: :show)
          requires_module :appointments
          # Registered after the gate so it runs BEFORE it: the gate reads the company from the context this opens.
          prepend_around_action :within_public_company
          rescue_from ::Appointments::Availability::InvalidRequest, with: :render_availability_invalid

          def show
            query = availability_query
            company = Current.context.company
            branch = open_branch!(company, query[:branch_id])
            services = services_in_order(::Appointments::Service.where(company_id: company.id), query[:service_ids])
            professional = query[:professional_id] == :any ? :any : branch_professionals(company, branch).find(query[:professional_id])
            ensure_range!(query)
            render json: ::Appointments::PublicAvailability.call(company:, branch:, services:, professional:, from_date: query[:from], to_date: query[:to])
          end

          private

          def query_names = super + [ "branch_id" ]

          # Opens the company's tenant from the slug in the route (the only thing the anonymous caller names). No company is a
          # 404 before the gate, so the gate always finds one.
          def within_public_company(&)
            found = ::Tenancy::PublicDirectory.company_by_slug(request.path_parameters[:slug])
            raise ActiveRecord::RecordNotFound, "No se encontró el recurso" unless found

            ::Tenancy.with_context(organization: found[:organization], company: found[:company], read_only: true, &)
          end

          # The company must be active and booking enabled at BOTH levels: a branch setting can override the company's, so
          # reading only the merged branch value would let a branch re-open what the company closed.
          def open_branch!(company, branch_id)
            branch = ::Tenancy::Directory.branch!(branch_id, company_id: company.id)
            raise ActiveRecord::RecordNotFound, "No se encontró el recurso" unless company.active? && branch.active? && public_booking_enabled?(company, branch)

            branch
          end

          def public_booking_enabled?(company, branch)
            [ ::Modules.settings_for(:appointments, company:), ::Modules.settings_for(:appointments, company:, branch:) ].all? { it["public_booking_enabled"] == true }
          end

          def branch_professionals(company, branch)
            ::Appointments::Professional.where(company_id: company.id,
                                               id: ::Appointments::ProfessionalBranchAssignment.where(company_id: company.id, branch_id: branch.id).select(:professional_id))
          end

          # The list is a shape the booking page controls, so a bad one is a 400, not a 404.
          def validate_service_ids!(ids)
            raise ActionController::BadRequest, "service_ids must have at most #{MAX_SERVICES} items" if ids.size > MAX_SERVICES
            raise ActionController::BadRequest, "service_ids must not repeat" if ids.uniq.size != ids.size
          end

          def ensure_range!(query)
            return if (query[:to] - query[:from]).to_i < MAX_RANGE_DAYS

            raise ::Appointments::Availability::InvalidRequest, [ { field: :to, code: :invalid_range } ]
          end

          def render_availability_invalid(error)
            visible = error.errors.all? { VISIBLE_ERRORS.include?([ it[:field], it[:code] ]) }
            render_problem(visible ? error : ActiveRecord::RecordNotFound.new("No se encontró el recurso"))
          end
        end
      end
    end
  end
end
