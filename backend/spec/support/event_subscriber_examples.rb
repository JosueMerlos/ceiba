# Un suscriptor registrado, entregado DOS veces con el mismo evento, produce un solo efecto (docs/architecture/12-testing-strategy.md,
# suite 6). Lo ejecuta spec/platform/events/events_suite_spec.rb sobre todos los suscriptores de los packs; un pack nuevo
# no necesita escribir nada. `payload:` es el payload con el que se construye el evento de muestra.
RSpec.shared_examples "un suscriptor idempotente" do |event_name, subscriber, payload: {}|
  let(:organization) { create(:organization) }

  it "ejecutado dos veces con el mismo evento produce un solo efecto (#{subscriber} <- #{event_name})" do
    original = Events::Subscriptions.find(event_name, subscriber)
    effects = 0
    spy = ->(event) { effects += 1 && original.handler.call(event) }
    Events::Subscriptions.register(event_name:, subscriber:, handler: spy, queue: original.queue)
    event = create_in(organization, :outbox_event, name: event_name, payload:)

    2.times do
      Events::DeliverJob.set("organization_id" => organization.id).perform_async(event.id, subscriber)
      Events::DeliverJob.drain
    end

    expect(effects).to eq(1)
  end
end
