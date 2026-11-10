require "rails_helper"

# The public API is SMALL on purpose: models, registry and services are private. Adding something to app/public is a
# design decision; this spec forces it to be a conscious one.
RSpec.describe "API pública de access" do
  let(:public_files) do
    root = Rails.root.join("packs/platform/access/app/public")
    root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s }
  end

  it "expone solo el registro de permisos, el principal, el alcance, la base de las policies, la autorización de controladores y los errores" do
    expect(public_files).to contain_exactly(
      "access.rb", "access/error.rb", "access/unknown_permission.rb", "access/organization_suspended.rb", "access/sync_refused.rb",
      "access/scope.rb", "access/reach.rb", "access/grant_role.rb", "access/base_policy.rb", "access/authorization.rb",
      "access/principal.rb", "access/principal/user.rb", "access/principal/system.rb", "access/principal/api_key.rb",
      "access/principal/public_token.rb"
    )
  end

  it "los modelos y servicios internos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Aaccess/(membership|role|permission|role_permission|grants|catalog_sync|permission_registry)\.rb\z}))
  end
end
