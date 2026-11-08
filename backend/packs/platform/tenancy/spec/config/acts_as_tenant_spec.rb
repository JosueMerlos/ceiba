require "rails_helper"

RSpec.describe "Configuración de acts_as_tenant" do
  it "exige tenant: una consulta sin tenant falla en lugar de devolver todo" do
    expect(ActsAsTenant.configuration.require_tenant).to be(true)
  end
end
