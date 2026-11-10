require "rails_helper"

# The public API of audit is SMALL on purpose: record (record, record_auth) and the domain errors. Models, diff and
# recorders are internal. Adding something to app/public is a design decision.
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
