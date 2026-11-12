require "rails_helper"

RSpec.describe Appointments::Availability::ServicePlan do
  def item(id, duration, before: 0, after: 0, price: 0, kinds: [])
    described_class::Item.new(id:, duration_minutes: duration, buffer_before_minutes: before, buffer_after_minutes: after, price_minor: price,
                              required_kinds: kinds)
  end

  def plan(services, overrides: {}, currency: "NIO") = described_class.call(services:, overrides:, currency:)

  it "barba (20) + corte (30, buffer posterior de 10): duración 50, buffers de los bordes y bloque de 60", :aggregate_failures do
    result = plan([ item("barba", 20), item("corte", 30, after: 10) ])

    expect(result.duration_minutes).to eq(50)
    expect(result.buffer_before_minutes).to eq(0)
    expect(result.buffer_after_minutes).to eq(10)
    expect(result.block_minutes).to eq(60)
  end

  it "el buffer previo es el del PRIMER servicio y el posterior el del ÚLTIMO; los de en medio se ignoran", :aggregate_failures do
    result = plan([ item("a", 20, before: 5, after: 7), item("b", 30, before: 11, after: 13), item("c", 10, before: 17, after: 3) ])

    expect(result.duration_minutes).to eq(60)
    expect(result.buffer_before_minutes).to eq(5)
    expect(result.buffer_after_minutes).to eq(3)
    expect(result.block_minutes).to eq(68)
  end

  it "suma precios y duraciones base sin overrides, con la moneda de la empresa", :aggregate_failures do
    result = plan([ item("a", 30, price: 15_000), item("b", 20, price: 8_000) ], currency: "USD")

    expect(result.price_minor).to eq(23_000)
    expect(result.duration_minutes).to eq(50)
    expect(result.currency).to eq("USD")
  end

  it "el override de duración y de precio solo afecta al servicio que lo tiene", :aggregate_failures do
    services = [ item("a", 30, price: 15_000), item("b", 20, price: 8_000) ]

    result = plan(services, overrides: { "b" => { duration_minutes: 25, price_minor: 9_500 } })

    expect(result.duration_minutes).to eq(55)
    expect(result.price_minor).to eq(24_500)
  end

  it "un override con solo uno de los dos campos deja el otro en el valor base", :aggregate_failures do
    services = [ item("a", 30, price: 15_000) ]

    expect(plan(services, overrides: { "a" => { duration_minutes: 40, price_minor: nil } }).then { [ it.duration_minutes, it.price_minor ] }).to eq([ 40, 15_000 ])
    expect(plan(services, overrides: { "a" => { duration_minutes: nil, price_minor: 12_000 } }).then { [ it.duration_minutes, it.price_minor ] }).to eq([ 30, 12_000 ])
  end

  it "adversarial: un override de precio en 0 cuenta como 0 (gratis), no como sin override", :aggregate_failures do
    result = plan([ item("a", 30, price: 15_000), item("b", 20, price: 8_000) ], overrides: { "a" => { duration_minutes: nil, price_minor: 0 } })

    expect(result.price_minor).to eq(8_000)
  end

  it "los tipos de recurso requeridos se unen sin repetir y ordenados" do
    result = plan([ item("a", 30, kinds: %w[room]), item("b", 20), item("c", 10, kinds: %w[room]) ])

    expect(result.required_kinds).to eq(%w[room])
  end

  it "un servicio sin requisitos no añade tipos, y dos tipos distintos se conservan", :aggregate_failures do
    expect(plan([ item("a", 30), item("b", 20) ]).required_kinds).to eq([])
    expect(plan([ item("a", 30, kinds: %w[room]), item("b", 20, kinds: %w[chair]) ]).required_kinds).to eq(%w[chair room])
  end

  it "con un solo servicio el plan es el propio servicio", :aggregate_failures do
    result = plan([ item("a", 45, before: 5, after: 10, price: 100) ])

    expect([ result.duration_minutes, result.buffer_before_minutes, result.buffer_after_minutes, result.price_minor ]).to eq([ 45, 5, 10, 100 ])
  end
end
