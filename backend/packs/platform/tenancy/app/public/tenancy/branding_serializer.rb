module Tenancy
  # Public representation of a company's branding. Fields match components.schemas.Branding EXACTLY. Every value is null while
  # the company has not customized it (the platform default applies). `assets` carries one object per attached image with the
  # URLs of its variants: they are versioned (a replaced image is a new blob, so a new URL) and never point at the original.
  class BrandingSerializer < Api::Serializer
    # The brand's own columns, in the order they are published (also the fields a caller may write).
    FIELDS = Company::Branding::ATTRIBUTES

    attributes(*FIELDS)

    attribute :assets do |company|
      BrandingAssets::KINDS.index_with { |kind| BrandingSerializer.assets_for(company, kind) }
    end

    # URLs of the variants of one image, or nil when the company has none.
    def self.assets_for(company, kind)
      return unless company.public_send(kind).attached?

      company.branding_variants(kind).transform_values { |variant| variant_path(kind, variant) }
    end

    # The file name in the URL is generic: the one the user uploaded is never published.
    def self.variant_path(kind, variant)
      Rails.application.routes.url_helpers.rails_blob_representation_proxy_path(
        signed_blob_id: variant.blob.signed_id, variation_key: variant.variation.key, filename: "#{kind}.#{variant.variation.format.downcase}"
      )
    end
  end
end
