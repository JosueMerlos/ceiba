require "rails_helper"

RSpec.describe Appointments::Availability::LeastBusy do
  def day = Date.new(2026, 11, 16)

  def choose(candidates, load_by_day, on: day) = described_class.call(candidates:, load_by_day:, day: on)

  it "con dos candidatos gana el de menos citas ese día" do
    load = { "a" => { day => 3 }, "b" => { day => 1 } }

    expect(choose(%w[a b], load)).to eq("b")
  end

  it "con empate de carga gana el menor id, sea cual sea el orden de los candidatos", :aggregate_failures do
    load = { "a" => { day => 2 }, "b" => { day => 2 }, "c" => { day => 2 } }

    expect(choose(%w[c a b], load)).to eq("a")
    expect(choose(%w[b c], load)).to eq("b")
  end

  it "un candidato sin citas ese día gana a uno con citas, aunque tenga muchas otro día" do
    load = { "a" => { day => 1 }, "b" => { day + 1 => 9 } }

    expect(choose(%w[a b], load)).to eq("b")
  end

  it "un candidato ausente del mapa cuenta como carga 0" do
    expect(choose(%w[a b], { "a" => { day => 1 } })).to eq("b")
  end

  it "adversarial: una carga más baja con id mayor gana al id menor con más carga", :aggregate_failures do
    load = { "a" => { day => 2 }, "z" => { day => 0 } }

    expect(choose(%w[a z], load)).to eq("z")
    expect(choose(%w[z a], load)).to eq("z")
  end

  it "un solo candidato se devuelve tal cual" do
    expect(choose(%w[a], { "a" => { day => 5 } })).to eq("a")
  end

  it "sin candidatos no hay elección (nil)" do
    expect(choose([], {})).to be_nil
  end
end
