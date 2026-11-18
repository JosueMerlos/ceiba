module Api
  module Public
    module V1
      module Tenancy
        # A company's branding for anyone, with no session: the booking page (and the panel) paint the company's identity from it.
        # Inside this namespace `Tenancy` is Api::Public::V1::Tenancy: the pack's own constants are always written `::Tenancy`.
        #
        # It always revalidates (`Cache-Control: public, no-cache` + ETag) so a changed brand shows up without clearing any
        # cache, and the 304 is cheap. The ETag is the serializer's version plus the company's version: saving a brand bumps it, images included (see
        # Tenancy::BrandingAssets#touch!). An unknown slug, a suspended organization and an inactive company all answer the same 404.
        class BrandingsController < ::Api::BaseController
          skip_authentication!
          skip_authorization!(reason: "endpoint anónimo: no hay principal; solo expone colores, textos y URLs de imágenes de la marca de una empresa activa", only: :show)
          prepend_around_action :within_public_company

          def show
            company = Current.context.company
            expires_now
            return unless stale?(etag: [ ::Tenancy::BrandingSerializer::VERSION, company.cache_key_with_version ], public: true)

            render json: { data: ::Tenancy::BrandingSerializer.new(company).serializable_hash }
          end

          private

          # Opens the company's tenant from the slug in the route (the only thing the anonymous caller names).
          def within_public_company(&)
            found = ::Tenancy::PublicDirectory.company_by_slug(request.path_parameters[:slug])
            raise ActiveRecord::RecordNotFound unless found && found[:company].active?

            ::Tenancy.with_context(organization: found[:organization], company: found[:company], read_only: true, &)
          end
        end
      end
    end
  end
end
