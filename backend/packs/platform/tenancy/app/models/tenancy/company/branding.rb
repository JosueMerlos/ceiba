module Tenancy
  class Company
    # The company's identity: three colors, one of the curated fonts, a name and a tagline, and the logo, banner and favicon
    # images. NULL everywhere means "not customized": the platform default applies.
    #
    # The images are Active Storage attachments with NO background jobs (`dependent: false`, no analyzers, no preprocessed
    # variants): the sidekiq adapter would enqueue them outside the outbox. Their kinds and variants come from
    # Tenancy::BrandingAssets, which also does the work around them.
    module Branding
      extend ActiveSupport::Concern

      FONT_CHOICES = %w[figtree lora nunito].freeze
      COLOR_FORMAT = /\A#[0-9A-F]{6}\z/
      COLOR_ATTRIBUTES = %i[primary_color secondary_color accent_color].freeze
      ATTRIBUTES = (%i[brand_name tagline] + COLOR_ATTRIBUTES + %i[font_choice]).freeze

      included do
        # A blank value goes back to the default. Colors are uppercased; an inner space is NOT trimmed away (it stays invalid).
        normalizes :brand_name, :tagline, with: ->(value) { value.strip.presence }
        normalizes(*COLOR_ATTRIBUTES, with: ->(value) { value.blank? ? nil : value.upcase })
        normalizes :font_choice, with: ->(value) { value.strip.presence }

        validates :brand_name, length: { maximum: 80 }
        validates :tagline, length: { maximum: 140 }
        validates(*COLOR_ATTRIBUTES, format: { with: COLOR_FORMAT }, allow_nil: true)
        validates :font_choice, inclusion: { in: FONT_CHOICES }, allow_nil: true

        ::Tenancy::BrandingAssets::ASSETS.each do |kind, asset|
          has_one_attached kind, dependent: false do |attachable|
            asset.fetch(:variants).each { |name, transformations| attachable.variant name, **transformations }
          end
        end
      end

      # The branding fields as they are now, and as they are stored (before an unsaved assignment): the diff of an audit.
      def branding_attributes = ATTRIBUTES.index_with { |name| public_send(name) }
      def persisted_branding_attributes = ATTRIBUTES.index_with { |name| attribute_in_database(name) }

      # The variants of an attached image by name, in publication order, as the proxy will see them: rebuilt from their signed key.
      # A variant record is found by the digest of its transformations, and the key's JSON round trip turns symbols into strings,
      # so only the decoded form matches the digest the proxy looks up. Rendering one is `.processed`.
      def branding_variants(kind)
        attachment = public_send(kind)
        ::Tenancy::BrandingAssets.variant_names(kind).index_with { |name| attachment.blob.representation(attachment.variant(name).variation.key) }
      end
    end
  end
end
