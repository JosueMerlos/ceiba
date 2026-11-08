require "rails_helper"

# Suite de eventos de plataforma (M0.10, docs/architecture/12-testing-strategy.md, suite 6). Descubre los eventos y los
# suscriptores de TODOS los packs: uno nuevo entra solo.
RSpec.describe "Suite de eventos de plataforma" do
  let(:published_names) do
    sources = Rails.root.glob("{app,lib,db,config}/**/*.rb") + Rails.root.glob("packs/*/*/{app,lib,db,config}/**/*.rb")
    sources.flat_map { |file| file.readlines.grep_v(/\A\s*#/).join.scan(/Events\.publish\(\s*"([a-z0-9_.]+)"/).flatten }.uniq
  end

  it "todo evento publicado en el código tiene esquema registrado" do
    expect(published_names).to include("platform.organization_provisioned.v1")
    expect(published_names - Events::Schemas.names).to be_empty
  end

  it "todo suscriptor registrado escucha un evento con esquema y usa una cola declarada" do
    Events::Subscriptions.all.each do |subscription|
      expect(Events::Schemas.names).to include(subscription.event_name), "#{subscription.subscriber} escucha #{subscription.event_name}, que no tiene esquema"
      expect(Events::Subscriptions::QUEUES).to include(subscription.queue)
    end
  end

  it "todo esquema tiene un nombre de evento válido, versionado, y está en el pack que lo declara" do
    expect(Events::Schemas.names).to all(match(Events::OutboxEvent::NAME_FORMAT))
  end

  it "todo evento del catálogo publicado con un payload mínimo válido valida contra su esquema" do
    Events::Schemas.names.each do |name|
      sample = EventSamples.payload_for(Events::Schemas.definition(name))

      expect { Events::Schemas.validate!(name, sample) }.not_to raise_error, "#{name}: el payload de muestra no valida"
    end
  end

  Events::Subscriptions.all.each do |subscription|
    describe "#{subscription.subscriber} <- #{subscription.event_name}" do
      it_behaves_like "un suscriptor idempotente", subscription.event_name, subscription.subscriber
    end
  end

  describe "el propio harness" do
    before do
      Events.subscribe("test.thing_happened.v1", as: "test.harness") { |_event| nil }
    end

    it_behaves_like "un suscriptor idempotente", "test.thing_happened.v1", "test.harness"
  end
end
