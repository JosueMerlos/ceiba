require "rails_helper"

# The table of branding images is the single source of the kinds, their limits and their variants: the model's attachments and
# the validator are derived from it, so they cannot drift apart.
RSpec.describe Tenancy::BrandingAssets do
  it "cada tipo de la tabla es un adjunto de la empresa y a la inversa" do
    expect(Tenancy::Company.attachment_reflections.keys).to match_array(described_class::KINDS.map(&:to_s))
  end

  it "el modelo declara las variantes de la tabla, en el mismo orden" do
    declared = described_class::KINDS.to_h { |kind| [ kind, Tenancy::Company.reflect_on_attachment(kind).named_variants.keys ] }

    expect(declared).to eq(described_class::KINDS.to_h { |kind| [ kind, described_class.variant_names(kind) ] })
  end

  it "el límite de tamaño de cada tipo sale de la tabla" do
    expect(described_class::KINDS.map { |kind| described_class.max_bytes(kind) }).to eq([ 2.megabytes, 5.megabytes, 200.kilobytes ])
  end

  describe "#discard!" do
    it "sigue con los demás originales aunque borrar uno falle, y lo reporta" do
      company = create_in(create(:organization), :company)
      assets = described_class.new(company)
      uploads = %i[logo banner].to_h { |kind| [ kind, branding_upload(png_bytes(width: 300, height: 300), filename: "#{kind}.png", type: "image/png") ] }
      blobs = assets.stage(uploads, content_types: { logo: "image/png", banner: "image/png" })
      allow(Rails.error).to receive(:report)
      allow(blobs[:logo].service).to receive(:delete).and_wrap_original do |original, key|
        key == blobs[:logo].key ? raise(IOError, "disk") : original.call(key)
      end

      assets.discard!

      expect(Rails.error).to have_received(:report).with(an_instance_of(IOError), hash_including(handled: true))
      expect(blobs[:banner].service.exist?(blobs[:banner].key)).to be(false)
    end
  end
end
