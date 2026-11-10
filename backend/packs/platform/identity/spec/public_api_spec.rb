require "rails_helper"

# The public API of identity is SMALL on purpose: internal models and services are private and packwerk (privacy)
# enforces it from outside.
RSpec.describe "API pública de identity" do
  let(:root) { Rails.root.join("packs/platform/identity/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo Authenticate, CurrentSession, ProvisionUser, el principal y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "identity/authenticate.rb", "identity/current_session.rb", "identity/provision_user.rb", "identity/principal/user.rb",
      "identity/error.rb", "identity/invalid_credentials.rb", "identity/unauthenticated.rb",
      "identity/invalid_csrf_token.rb", "identity/forbidden_origin.rb"
    )
  end

  it "los modelos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Aidentity/(user|session)\.rb\z}))
  end
end
