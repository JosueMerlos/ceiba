require "rails_helper"
require "ci/pack_contract"

RSpec.describe "Pack modules/appointments" do
  it "cumple el contrato de packs (capa, enforcement, visibilidad)" do
    violations = PackContract.new(Rails.root).violations.select { |violation| violation.start_with?("packs/modules/appointments:") }

    expect(violations).to be_empty
  end

  it "tiene su manifest.rb" do
    expect(Rails.root.join("packs/modules/appointments/manifest.rb")).to exist
  end
end
