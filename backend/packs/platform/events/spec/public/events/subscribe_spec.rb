require "rails_helper"

RSpec.describe Events, ".subscribe" do
  let(:handler) { ->(_event) { :handled } }

  it "registra un suscriptor con su nombre, el evento y la cola de entrega" do
    described_class.subscribe("test.thing_happened.v1", as: "test.audit", queue: "notifications", &handler)

    expect(Events::Subscriptions.for_event("test.thing_happened.v1"))
      .to contain_exactly(have_attributes(subscriber: "test.audit", event_name: "test.thing_happened.v1", queue: "notifications"))
  end

  it "la cola por defecto es critical (entregas)" do
    described_class.subscribe("test.thing_happened.v1", as: "test.audit", &handler)

    expect(Events::Subscriptions.for_event("test.thing_happened.v1").first.queue).to eq("critical")
  end

  it "acepta un objeto que responda a call en lugar de un bloque" do
    callable = Class.new { def call(event) = event.name }.new

    described_class.subscribe("test.thing_happened.v1", as: "test.audit", handler: callable)

    expect(Events::Subscriptions.find("test.thing_happened.v1", "test.audit").handler.call(Events::Event.new(id: "x", name: "n", organization_id: "o", payload: {}, metadata: {}, occurred_at: Time.current))).to eq("n")
  end

  it "varios suscriptores del mismo evento se conservan en orden de registro" do
    described_class.subscribe("test.thing_happened.v1", as: "test.a", &handler)
    described_class.subscribe("test.thing_happened.v1", as: "test.b", &handler)

    expect(Events::Subscriptions.for_event("test.thing_happened.v1").map(&:subscriber)).to eq(%w[test.a test.b])
  end

  it "registrar el mismo suscriptor y evento otra vez lo REEMPLAZA (idempotente con config.to_prepare)" do
    described_class.subscribe("test.thing_happened.v1", as: "test.a", queue: "low", &handler)
    described_class.subscribe("test.thing_happened.v1", as: "test.a", queue: "default", &handler)

    expect(Events::Subscriptions.for_event("test.thing_happened.v1")).to contain_exactly(have_attributes(queue: "default"))
  end

  it "el mismo suscriptor puede escuchar eventos distintos" do
    described_class.subscribe("test.a.v1", as: "test.audit", &handler)
    described_class.subscribe("test.b.v1", as: "test.audit", &handler)

    expect([ "test.a.v1", "test.b.v1" ].map { |name| Events::Subscriptions.for_event(name).size }).to eq([ 1, 1 ])
  end

  it "rechaza una cola que no existe" do
    expect { described_class.subscribe("test.a.v1", as: "test.a", queue: "inventada", &handler) }.to raise_error(ArgumentError, /cola/)
  end

  it "rechaza un nombre de evento mal formado y un suscriptor sin nombre" do
    expect { described_class.subscribe("mal nombre", as: "test.a", &handler) }.to raise_error(ArgumentError, /evento/)
    expect { described_class.subscribe("test.a.v1", as: "", &handler) }.to raise_error(ArgumentError, /suscriptor/)
  end

  it "rechaza no dar ni bloque ni handler" do
    expect { described_class.subscribe("test.a.v1", as: "test.a") }.to raise_error(ArgumentError, /call/)
  end

  it "devuelve [] para un evento sin suscriptores" do
    expect(Events::Subscriptions.for_event("test.nadie.v1")).to eq([])
  end
end
