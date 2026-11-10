require "rails_helper"

# The public API of idempotency is SMALL on purpose: the controller concern and the domain errors. The model and the
# processor are internal.
RSpec.describe "API pública de idempotency" do
  let(:root) { Rails.root.join("packs/platform/idempotency/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo Idempotency::Idempotent y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "idempotency/idempotent.rb", "idempotency/error.rb", "idempotency/key_reused.rb", "idempotency/key_required.rb",
      "idempotency/key_invalid.rb", "idempotency/missing_context.rb", "idempotency/request_in_progress.rb"
    )
  end
end
