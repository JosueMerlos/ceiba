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
end
