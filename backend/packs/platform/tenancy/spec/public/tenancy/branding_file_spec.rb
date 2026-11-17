require "rails_helper"

# Tenancy::BrandingFile: decides whether an uploaded image may become a branding asset, by what the bytes ARE (magic bytes,
# never the file name or the declared type), their size and their dimensions. Returns the detected content type.
RSpec.describe Tenancy::BrandingFile do
  def check(upload, kind: :logo) = described_class.call(upload, kind:)

  def rejection_code(upload, kind: :logo)
    check(upload, kind:)
    nil
  rescue described_class::Rejected => error
    error.code
  end

  it "acepta un PNG real y devuelve image/png" do
    upload = branding_upload(png_bytes, filename: "logo.png", type: "image/png")

    expect(check(upload)).to eq("image/png")
  end

  it "acepta un PNG renombrado a .jpg y devuelve el tipo real, no el declarado" do
    upload = branding_upload(png_bytes, filename: "png-as.jpg", type: "image/jpeg")

    expect(check(upload)).to eq("image/png")
  end

  it "deja el archivo listo para leerse otra vez desde el principio" do
    upload = branding_upload(png_bytes, filename: "logo.png", type: "image/png")

    check(upload)

    expect(upload.read.bytesize).to eq(png_bytes.bytesize)
  end

  it "rechaza un SVG renombrado a .png aunque declare image/png (invalid_file_type)" do
    upload = branding_upload(BrandingImages::SVG, filename: "svg-as.png", type: "image/png")

    expect(rejection_code(upload)).to eq(:invalid_file_type)
  end

  it "rechaza un GIF real (invalid_file_type)" do
    upload = branding_upload(BrandingImages::GIF, filename: "anim.gif", type: "image/gif")

    expect(rejection_code(upload)).to eq(:invalid_file_type)
  end

  it "rechaza texto que finge ser PNG (invalid_file_type)" do
    upload = branding_upload("no soy una imagen", filename: "logo.png", type: "image/png")

    expect(rejection_code(upload)).to eq(:invalid_file_type)
  end

  it "rechaza un PNG con cabecera válida pero cuerpo truncado (invalid_file_type)" do
    upload = branding_upload(png_bytes.byteslice(0, 40), filename: "logo.png", type: "image/png")

    expect(rejection_code(upload)).to eq(:invalid_file_type)
  end

  describe "tamaño" do
    it "acepta un logo de exactamente 2 MB (borde)" do
      upload = branding_upload(png_bytes(pad_to: 2.megabytes), filename: "logo.png", type: "image/png")

      expect(check(upload)).to eq("image/png")
    end

    it "rechaza un logo de 2 MB + 1 byte (file_too_large)" do
      upload = branding_upload(png_bytes(pad_to: 2.megabytes + 1), filename: "logo.png", type: "image/png")

      expect(rejection_code(upload)).to eq(:file_too_large)
    end

    it "rechaza un favicon de 200 KB + 1 byte, pero acepta ese mismo tamaño en un banner" do
      bytes = png_bytes(pad_to: 200.kilobytes + 1)

      expect([ rejection_code(branding_upload(bytes, filename: "f.png", type: "image/png"), kind: :favicon),
               rejection_code(branding_upload(bytes, filename: "b.png", type: "image/png"), kind: :banner) ]).to eq([ :file_too_large, nil ])
    end

    it "rechaza un banner de 5 MB + 1 byte (file_too_large)" do
      upload = branding_upload(png_bytes(pad_to: 5.megabytes + 1), filename: "banner.png", type: "image/png")

      expect(rejection_code(upload, kind: :banner)).to eq(:file_too_large)
    end
  end

  describe "dimensiones" do
    it "rechaza un PNG de 8000x10 aunque pese pocos bytes (image_too_large)" do
      bytes = png_bytes(width: 8000, height: 10)
      upload = branding_upload(bytes, filename: "huge.png", type: "image/png")

      expect([ bytes.bytesize < 20.kilobytes, rejection_code(upload) ]).to eq([ true, :image_too_large ])
    end

    it "acepta 4096 px de lado y rechaza 4097 (borde)" do
      accepted = branding_upload(png_bytes(width: 4096, height: 2), filename: "a.png", type: "image/png")
      rejected = branding_upload(png_bytes(width: 2, height: 4097), filename: "b.png", type: "image/png")

      expect([ rejection_code(accepted), rejection_code(rejected) ]).to eq([ nil, :image_too_large ])
    end
  end
end
