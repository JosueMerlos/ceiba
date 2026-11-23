require "rails_helper"

# Tenancy::Storage::RepresentationsController overrides a PRIVATE hook of Active Storage's proxy controller to never render an
# image on an anonymous GET. If an Active Storage upgrade renames or removes that hook, the override would silently stop
# applying and the proxy would process images again: this fails first.
RSpec.describe Tenancy::Storage::RepresentationsController do
  it "sigue existiendo el gancho privado set_representation de Active Storage que se sobrescribe" do
    expect(ActiveStorage::Representations::ProxyController.private_method_defined?(:set_representation)).to be(true)
  end
end
