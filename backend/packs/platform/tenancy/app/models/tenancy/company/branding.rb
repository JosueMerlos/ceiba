module Tenancy
  class Company
    # The company's identity: three colors, one of the curated fonts, a name and a tagline, and the logo, banner and favicon
    # images. NULL everywhere means "not customized": the platform default applies.
    #
    # The images are Active Storage attachments with NO background jobs (`dependent: false`, no analyzers, no preprocessed
    # variants): the sidekiq adapter would enqueue them outside the outbox. The variants are the only thing ever served; they are
    # rendered synchronously by Access::UpdateBranding and re-encoded (so the original, with its metadata, is never exposed).
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

        has_one_attached :logo, dependent: false do |attachable|
          attachable.variant :x1, resize_to_limit: [ nil, 64 ], format: :webp, saver: { strip: true }
          attachable.variant :x2, resize_to_limit: [ nil, 128 ], format: :webp, saver: { strip: true }
        end
        has_one_attached :banner, dependent: false do |attachable|
          attachable.variant :wide, resize_to_fill: [ 1600, 900 ], format: :webp, saver: { strip: true }
          attachable.variant :standard, resize_to_fill: [ 1200, 900 ], format: :webp, saver: { strip: true }
        end
        has_one_attached :favicon, dependent: false do |attachable|
          attachable.variant :icon32, resize_to_fill: [ 32, 32 ], format: :png, saver: { strip: true }
          attachable.variant :icon180, resize_to_fill: [ 180, 180 ], format: :png, saver: { strip: true }
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
        VARIANTS.fetch(kind).index_with { |name| attachment.blob.representation(attachment.variant(name).variation.key) }
      end

      # Attachments touch their record with touch_later, which runs when the outermost transaction commits: after the tenant
      # block ended, where a write to a tenant table is refused. Touching right away keeps it inside the tenant.
      def touch_later(*names) = persisted? ? touch(*names) : super

      # Variant names per attachment, in the order they are rendered and published.
      VARIANTS = { logo: %i[x1 x2], banner: %i[wide standard], favicon: %i[icon32 icon180] }.freeze
    end
  end
end
