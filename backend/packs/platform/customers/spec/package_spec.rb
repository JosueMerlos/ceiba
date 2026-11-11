require "rails_helper"
require "ci/pack_contract"

RSpec.describe "Pack platform/customers" do
  it "cumple el contrato de packs (capa, enforcement)" do
    violations = PackContract.new(Rails.root).violations.select { |violation| violation.start_with?("packs/platform/customers:") }

    expect(violations).to be_empty
  end
end
