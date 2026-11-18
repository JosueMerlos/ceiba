module Api
  module V1
    module Access
      # The branding of the route's company. The context (organization and company) is already resolved and validated, so a
      # company outside the principal's reach is a 404 before the policy runs. PATCH is multipart/form-data (the images travel in
      # it) or JSON when only text changes; a missing field is left alone, an empty one goes back to the platform default.
      class BrandingsController < ::Api::BaseController
        FIELDS = ::Tenancy::BrandingSerializer::FIELDS.index_with { String }.freeze

        def show
          company = Current.context.company
          authorize company, :show?, policy_class: ::Access::BrandingPolicy
          render_branding(company)
        end

        def update
          company = Current.context.company
          authorize company, :update?, policy_class: ::Access::BrandingPolicy
          render_branding(::Access::UpdateBranding.call(company:, attributes: typed_params(FIELDS), files: uploads, remove: removals))
        end

        private

        def render_branding(company)
          render json: { data: ::Tenancy::BrandingSerializer.new(company).serializable_hash }
        end

        # Only real uploads: a text value in a file field is a malformed request, not a validation error. An empty one is "no file
        # selected" (a form submits it for an untouched file input).
        def uploads
          ::Tenancy::BrandingAssets::KINDS.filter_map do |kind|
            value = request.request_parameters[kind.to_s]
            next if value.nil? || value == ""
            raise ActionController::BadRequest, "#{kind} debe ser un archivo" unless value.is_a?(ActionDispatch::Http::UploadedFile)

            [ kind, value ]
          end.to_h
        end

        def removals
          value = request.request_parameters["remove"]
          return [] if value.nil?

          kinds = ::Tenancy::BrandingAssets::KINDS.map(&:to_s)
          raise ActionController::BadRequest, "remove debe ser una lista de #{kinds.join(', ')}" unless value.is_a?(Array) && value.all? { kinds.include?(it) }

          value
        end
      end
    end
  end
end
