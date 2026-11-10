require "rails_helper"

# Tenancy's public API is SMALL on purpose: internal models and services are private and packwerk (privacy) blocks outside
# access. Adding something to app/public is a design decision: this spec forces it to be made consciously.
RSpec.describe "API pública de tenancy" do
  let(:public_files) do
    Rails.root.join("packs/platform/tenancy/app/public").glob("**/*.rb").map { |file| file.relative_path_from(Rails.root.join("packs/platform/tenancy/app/public")).to_s }
  end

  it "expone solo with_context, el contexto, la provisión (y altas adicionales), el Directory de lectura, los serializers y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "tenancy.rb", "tenancy/context.rb", "tenancy/provision_organization.rb", "tenancy/add_company.rb", "tenancy/add_branch.rb",
      "tenancy/error.rb", "tenancy/inconsistent_context.rb", "tenancy/provisioning_failed.rb",
      "tenancy/tenant_write_guard.rb", "tenancy/tenant_mismatch.rb", "tenancy/tenant_is_immutable.rb",
      "tenancy/directory.rb", "tenancy/organization_serializer.rb", "tenancy/organization_summary_serializer.rb", "tenancy/company_serializer.rb", "tenancy/branch_serializer.rb"
    )
  end

  it "los modelos y servicios internos no están en app/public" do
    expect(public_files).not_to include(a_string_matching(%r{\Atenancy/(organization|company|branch|failure_translator)\.rb\z}))
  end
end
