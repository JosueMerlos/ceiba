require "rails_helper"

# La API pública de events es CHICA a propósito: publicar, suscribirse, el evento, los esquemas y los errores. El
# outbox, el relay, las entregas y las purgas son internos. Añadir algo a app/public es una decisión de diseño.
RSpec.describe "API pública de events" do
  let(:root) { Rails.root.join("packs/platform/events/app/public") }
  let(:public_files) { root.glob("**/*.rb").map { |file| file.relative_path_from(root).to_s } }

  it "expone solo publish/subscribe, el evento, el registro de suscriptores y esquemas y los errores de dominio" do
    expect(public_files).to contain_exactly(
      "events.rb", "events/event.rb", "events/subscription.rb", "events/subscriptions.rb", "events/schemas.rb",
      "events/error.rb", "events/not_in_transaction.rb", "events/unknown_event.rb", "events/invalid_payload.rb", "events/unknown_subscriber.rb"
    )
  end

  it "los modelos, el relay, los jobs y las purgas no están en app/public" do
    expect(public_files).not_to include(a_string_matching(/outbox|processed|relay|deliver|purge|lag|cross_tenant/))
  end
end
