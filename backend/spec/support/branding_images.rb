require "zlib"

# Real image bytes generated at runtime (no binaries in the repository): a valid PNG of any size, optionally padded with
# trailing bytes after IEND (decoders ignore them) to land exactly on a size limit, plus an uploaded-file wrapper like the
# one a multipart request produces.
module BrandingImages
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
  SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>'.freeze
  # The smallest valid GIF (1x1).
  GIF = "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7".unpack1("m").freeze

  def png_bytes(width: 4, height: 4, color: [ 47, 138, 102 ], pad_to: nil)
    row = [ 0, *color * width ].pack("C*")
    png = PNG_SIGNATURE +
          png_chunk("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
          png_chunk("IDAT", Zlib::Deflate.deflate(row * height)) +
          png_chunk("IEND", "".b)
    pad_to ? png + ("\0".b * (pad_to - png.bytesize)) : png
  end

  def branding_upload(bytes, filename:, type:)
    tempfile = Tempfile.new([ "branding", File.extname(filename) ], binmode: true)
    tempfile.write(bytes)
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type:)
  end

  # Attaches a real image to a company the way Access::UpdateBranding does (original uploaded, no identification, no analysis:
  # either would enqueue a job) and, unless `process: false`, renders its variants once the attach has committed. Returns the
  # reloaded company.
  def attach_branding_image(organization, company, kind = :logo, color: [ 47, 138, 102 ], process: true)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(png_bytes(width: 300, height: 300, color:)), filename: "#{kind}.png", content_type: "image/png", identify: false,
      metadata: { "identified" => true, "analyzed" => true }
    )
    with_tenant(organization) do
      company.public_send(kind).attach(blob)
      company.touch
    end
    company.branding_variants(kind).each_value(&:processed) if process
    with_tenant(organization) { company.reload }
  end

  private

  def png_chunk(type, data)
    [ data.bytesize ].pack("N") + type.b + data + [ Zlib.crc32(type.b + data) ].pack("N")
  end
end

RSpec.configure { |config| config.include BrandingImages }
