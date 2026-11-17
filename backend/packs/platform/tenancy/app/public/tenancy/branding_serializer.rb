module Tenancy
  # Public representation of a company's branding. Fields match components.schemas.Branding EXACTLY. Every value is null while
  # the company has not customized it (the platform default applies). `assets` carries one object per attached image with the
  # URLs of its variants: they are versioned (a replaced image is a new blob, so a new URL) and never point at the original.
  class BrandingSerializer < Api::Serializer
    attributes :brand_name, :tagline, :primary_color, :secondary_color, :accent_color, :font_choice

    attribute :assets do |company|
      Company::Branding::VARIANTS.keys.to_h do |kind|
        [ kind, company.public_send(kind).attached? ? company.branding_variants(kind).transform_values { |variant| BrandingSerializer.variant_path(kind, variant) } : nil ]
      end
    end

    # The file name in the URL is generic: the one the user uploaded is never published.
    def self.variant_path(kind, variant)
      Rails.application.routes.url_helpers.rails_blob_representation_proxy_path(
        signed_blob_id: variant.blob.signed_id, variation_key: variant.variation.key, filename: "#{kind}.#{variant.variation.format.downcase}"
      )
    end
  end
end
