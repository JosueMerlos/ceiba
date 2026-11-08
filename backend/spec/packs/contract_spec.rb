require "rails_helper"
require "ci/pack_contract"

# Contrato GLOBAL: recorre todos los packs/*/* reales. No depende de que cada pack traiga su propio
# spec (que se podría borrar): editar un package.yml para saltarse el aislamiento rompe este spec.
RSpec.describe PackContract do
  it "se cumple en todos los packs del repositorio" do
    expect(described_class.new(Rails.root).violations).to be_empty
  end
end
