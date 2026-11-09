require "rails_helper"

# La API pública de identity es CHICA a propósito (docs/architecture/02-modular-monolith.md): modelos y servicios
# internos son privados y packwerk (privacy) lo impide desde fuera.
RSpec.describe "API pública de identity" do
  let(:root) { Rails.root.join("packs/platform/identity/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo Authenticate, CurrentSession, el principal y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "identity/authenticate.rb", "identity/current_session.rb", "identity/principal/user.rb",
      "identity/error.rb", "identity/invalid_credentials.rb", "identity/unauthenticated.rb",
      "identity/invalid_csrf_token.rb", "identity/forbidden_origin.rb"
    )
  end

  it "los modelos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Aidentity/(user|session)\.rb\z}))
  end
end
