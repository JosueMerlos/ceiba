require "rails_helper"

# La API pública de tenancy es CHICA a propósito (docs/architecture/02-modular-monolith.md): modelos y servicios internos
# son privados y packwerk (privacy) lo impide desde fuera. Añadir algo a app/public es una decisión de diseño: este spec
# obliga a hacerla a conciencia.
RSpec.describe "API pública de tenancy" do
  let(:public_files) do
    Rails.root.join("packs/platform/tenancy/app/public").glob("**/*.rb").map { |file| file.relative_path_from(Rails.root.join("packs/platform/tenancy/app/public")).to_s }
  end

  it "expone solo with_context, el contexto, la provisión (y altas adicionales) y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "tenancy.rb", "tenancy/context.rb", "tenancy/provision_organization.rb", "tenancy/add_company.rb", "tenancy/add_branch.rb",
      "tenancy/error.rb", "tenancy/inconsistent_context.rb", "tenancy/provisioning_failed.rb",
      "tenancy/tenant_write_guard.rb", "tenancy/tenant_mismatch.rb", "tenancy/tenant_is_immutable.rb"
    )
  end

  it "los modelos y servicios internos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Atenancy/(organization|company|branch|failure_translator)\.rb\z}))
  end
end
