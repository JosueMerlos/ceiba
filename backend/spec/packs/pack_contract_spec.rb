require "rails_helper"
require "ci/pack_contract"

# GLOBAL contract: walks all the real packs/*/*. Does not depend on each pack shipping its own spec (which could be
# deleted): editing a package.yml to skip isolation breaks this spec.
RSpec.describe PackContract do
  it "se cumple en todos los packs del repositorio" do
    expect(described_class.new(Rails.root).violations).to be_empty
  end
end
