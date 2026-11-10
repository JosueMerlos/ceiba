# A registered subscriber, delivered TWICE with the same event, produces a single effect. events_suite_spec runs it over
# every pack's subscribers; a new pack needs to write nothing. `payload:` is the payload the sample event is built with.
RSpec.shared_examples "un suscriptor idempotente" do |event_name, subscriber, payload: {}|
  let(:organization) { create(:organization) }

  it "ejecutado dos veces con el mismo evento produce un solo efecto (#{subscriber} <- #{event_name})" do
    original = Events::Subscriptions.find(event_name, subscriber)
    effects = 0
    spy = lambda do |event|
      effects += 1
      original.handler.call(event)
    end
    Events::Subscriptions.register(event_name:, subscriber:, handler: spy, queue: original.queue)
    event = create_in(organization, :outbox_event, name: event_name, payload:)

    2.times do
      Events::DeliverJob.set("organization_id" => organization.id).perform_async(event.id, subscriber)
      Events::DeliverJob.drain
    end

    expect(effects).to eq(1)
  end
end
