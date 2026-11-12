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
        # before anything else), then the shape of the query, the doors (PublicAvailability::Gate) and the use case.
        class AvailabilityController < ::Api::BaseController
          include ::Modules::RequiresModule
          include ::Appointments::AvailabilityQuery

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
            query = public_query
            company = Current.context.company
            opening = ::Appointments::PublicAvailability::Gate.open!(company:, branch_id: query[:branch_id], service_ids: query[:service_ids],
                                                                     professional_id: query[:professional_id])
            render json: ::Appointments::PublicAvailability.call(company:, **opening.to_h, from_date: query[:from], to_date: query[:to])
          end

          private

          # The list is a shape the booking page controls, so a bad one is a 400, not a 404.
          def public_query
            query = availability_query(extra_uuids: %i[branch_id])
            ids = query[:service_ids]
            raise ActionController::BadRequest, "service_ids must have at most #{MAX_SERVICES} items" if ids.size > MAX_SERVICES
            raise ActionController::BadRequest, "service_ids must not repeat" if ids.uniq.size != ids.size

            query
          end

          # Opens the company's tenant from the slug in the route (the only thing the anonymous caller names). No company is a
          # 404 before the module gate, so the gate always finds one.
          def within_public_company(&)
            found = ::Tenancy::PublicDirectory.company_by_slug(request.path_parameters[:slug])
            raise ::Appointments::PublicAvailability::Closed unless found

            ::Tenancy.with_context(organization: found[:organization], company: found[:company], read_only: true, &)
          end

          def render_availability_invalid(error)
            visible = error.errors.all? { VISIBLE_ERRORS.include?([ it[:field], it[:code] ]) }
            render_problem(visible ? error : ::Appointments::PublicAvailability::Closed.new)
          end
        end
      end
    end
  end
end
