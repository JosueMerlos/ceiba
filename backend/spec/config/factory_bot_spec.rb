require "rails_helper"

RSpec.describe "Configuración de FactoryBot" do
  it "expone la sintaxis corta (build, create, ...) en los specs" do
    expect(self).to respond_to(:build, :create, :build_stubbed)
  end

  it "todas las factories definidas son válidas" do
    expect { FactoryBot.lint(traits: true) }.not_to raise_error
  end
end
