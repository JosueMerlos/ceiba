module Tenancy
  module Storage
    # The only way a file leaves the application: a branding variant already rendered, through its signed URL. It is Active
    # Storage's proxy controller with one change: it never processes anything. An anonymous GET must not run libvips nor write
    # a row, so a variation that has no record is a 404; the variants are rendered when the branding is saved. A transformation
    # the server did not sign cannot be asked for either (its key fails the signature check). It does not inherit
    # Api::BaseController: it is anonymous by design, the URL is the capability, and it serves bytes, not JSON.
    class RepresentationsController < ActiveStorage::Representations::ProxyController
      rescue_from ActiveStorage::FileNotFoundError, with: -> { head :not_found }

      private

      def set_representation
        variant = @blob.representation(params[:variation_key])
        return head :not_found unless variant.image&.attached?

        @representation = variant
      rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveStorage::UnrepresentableError
        head :not_found
      end
    end
  end
end
