module Tenancy
  # Decides whether an uploaded image may become a branding asset, by what its bytes ARE: the type comes from the magic
  # bytes (never the file name nor the declared type, which the client controls), the size from the file and the dimensions
  # from the image header, so a tiny file that decodes into a huge bitmap is refused before anything decodes it. An SVG
  # renamed to .png is not a PNG, so it is refused.
  #
  #   Tenancy::BrandingFile.call(upload, kind: :logo)  # => "image/png"; raises Tenancy::BrandingFile::Rejected otherwise
  #
  # Returns the DETECTED content type: it is the one to store, so Active Storage never identifies the file again by its name.
  module BrandingFile
    ALLOWED_TYPES = %w[image/png image/jpeg image/webp].freeze
    MAX_SIDE = 4096

    # `code` is stable (it ends in the problem's errors[]): invalid_file_type, file_too_large or image_too_large.
    class Rejected < Error
      attr_reader :code

      def initialize(code, **interpolations)
        @code = code
        super(I18n.t("tenancy.branding_file.#{code}", **interpolations))
      end
    end

    module_function

    def call(upload, kind:)
      file = upload.tempfile
      limit = BrandingAssets.max_bytes(kind)
      raise Rejected.new(:file_too_large, limit: ActiveSupport::NumberHelper.number_to_human_size(limit)) if file.size > limit

      content_type = detect(file)
      raise Rejected, :invalid_file_type unless ALLOWED_TYPES.include?(content_type)

      check_image(file)
      content_type
    ensure
      upload.tempfile.rewind if upload.respond_to?(:tempfile)
    end

    # Magic bytes only: no name and no declared type are handed to Marcel.
    def detect(file)
      file.rewind
      Marcel::MimeType.for(file)
    end

    # The header gives the dimensions without decoding; the pixels are then read once, sequentially, so a truncated or corrupt
    # file fails here and not later, while rendering the variants.
    def check_image(file)
      image = Vips::Image.new_from_file(file.path, access: :sequential, fail: true)
      raise Rejected, :image_too_large if [ image.width, image.height ].max > MAX_SIDE

      image.avg
    rescue Vips::Error
      raise Rejected, :invalid_file_type
    end
    private_class_method :detect, :check_image
  end
end
