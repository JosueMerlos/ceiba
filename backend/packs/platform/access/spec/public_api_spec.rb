require "rails_helper"

# La API pública de access es CHICA a propósito (docs/architecture/02-modular-monolith.md): modelos, registro y servicios son
# privados. Añadir algo a app/public es una decisión de diseño: este spec obliga a hacerla a conciencia.
RSpec.describe "API pública de access" do
  let(:public_files) do
    root = Rails.root.join("packs/platform/access/app/public")
    root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s }
  end

  it "expone solo el registro de permisos, el principal, el alcance, la base de las policies, la autorización de controladores y los errores" do
    expect(public_files).to contain_exactly(
      "access.rb", "access/error.rb", "access/unknown_permission.rb", "access/organization_suspended.rb",
      "access/scope.rb", "access/reach.rb", "access/grant_role.rb", "access/base_policy.rb", "access/authorization.rb",
      "access/principal.rb", "access/principal/user.rb", "access/principal/system.rb", "access/principal/api_key.rb",
      "access/principal/public_token.rb"
    )
  end

  it "los modelos y servicios internos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Aaccess/(membership|role|permission|role_permission|grants|catalog_sync|permission_registry)\.rb\z}))
  end
end
