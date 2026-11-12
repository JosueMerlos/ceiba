require "rails_helper"

RSpec.describe Appointments::Availability::Interval do
  def at(hour, minute = 0) = Time.utc(2026, 1, 5, hour, minute)

  def interval(from, to) = described_class.new(starts_at: at(*from), ends_at: at(*to))

  describe "construcción" do
    it "rechaza un inicio igual al fin" do
      expect { described_class.new(starts_at: at(9), ends_at: at(9)) }.to raise_error(ArgumentError)
    end

    it "rechaza un inicio posterior al fin" do
      expect { described_class.new(starts_at: at(10), ends_at: at(9)) }.to raise_error(ArgumentError)
    end

    it "es inmutable y compara por valor" do
      expect(interval([ 9 ], [ 10 ])).to eq(interval([ 9 ], [ 10 ])).and be_frozen
    end
  end

  describe "#duration" do
    it "devuelve los segundos entre inicio y fin" do
      expect(interval([ 9 ], [ 10, 30 ]).duration).to eq(5400)
    end
  end

  describe "#overlaps?" do
    it "es verdadero con un solape parcial, en ambos sentidos", :aggregate_failures do
      expect(interval([ 9 ], [ 11 ]).overlaps?(interval([ 10 ], [ 12 ]))).to be(true)
      expect(interval([ 10 ], [ 12 ]).overlaps?(interval([ 9 ], [ 11 ]))).to be(true)
    end

    it "es verdadero cuando uno contiene al otro" do
      expect(interval([ 9 ], [ 13 ]).overlaps?(interval([ 10 ], [ 11 ]))).to be(true)
    end

    it "es falso para intervalos adyacentes (semiabierto)", :aggregate_failures do
      expect(interval([ 9 ], [ 10 ]).overlaps?(interval([ 10 ], [ 11 ]))).to be(false)
      expect(interval([ 10 ], [ 11 ]).overlaps?(interval([ 9 ], [ 10 ]))).to be(false)
    end

    it "es falso para intervalos disjuntos" do
      expect(interval([ 9 ], [ 10 ]).overlaps?(interval([ 11 ], [ 12 ]))).to be(false)
    end
  end

  describe "#cover?" do
    it "cubre un intervalo idéntico y uno que comparte un borde", :aggregate_failures do
      expect(interval([ 9 ], [ 13 ]).cover?(interval([ 9 ], [ 13 ]))).to be(true)
      expect(interval([ 9 ], [ 13 ]).cover?(interval([ 9 ], [ 10 ]))).to be(true)
      expect(interval([ 9 ], [ 13 ]).cover?(interval([ 12 ], [ 13 ]))).to be(true)
    end

    it "no cubre uno que se asoma un minuto por cualquier lado", :aggregate_failures do
      expect(interval([ 9 ], [ 13 ]).cover?(interval([ 8, 59 ], [ 10 ]))).to be(false)
      expect(interval([ 9 ], [ 13 ]).cover?(interval([ 12 ], [ 13, 1 ]))).to be(false)
    end

    it "no cubre uno disjunto" do
      expect(interval([ 9 ], [ 10 ]).cover?(interval([ 10 ], [ 11 ]))).to be(false)
    end
  end
end
