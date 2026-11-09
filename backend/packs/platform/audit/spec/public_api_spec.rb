require "rails_helper"

# La API pública de audit es CHICA a propósito: registrar (record, record_auth) y los errores de dominio. Los modelos, el
# diff y los registradores son internos. Añadir algo a app/public es una decisión de diseño.
RSpec.describe "API pública de audit" do
  let(:root) { Rails.root.join("packs/platform/audit/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo Audit.record/record_auth y los errores de dominio" do
    expect(public_files).to contain_exactly("audit.rb", "audit/error.rb", "audit/no_context.rb")
  end

  it "los modelos, el diff y los registradores no están en app/public" do
    expect(public_files).not_to include(a_string_matching(/event|diff|recorder|actor/))
  end
end
