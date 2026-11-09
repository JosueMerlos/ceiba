require "rails_helper"

# La API pública de idempotency es CHICA a propósito: el concern de controlador y los errores de dominio. El modelo y el
# procesador son internos.
RSpec.describe "API pública de idempotency" do
  let(:root) { Rails.root.join("packs/platform/idempotency/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo Idempotency::Idempotent y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "idempotency/idempotent.rb", "idempotency/error.rb", "idempotency/key_reused.rb", "idempotency/key_required.rb",
      "idempotency/key_invalid.rb", "idempotency/missing_context.rb"
    )
  end
end
