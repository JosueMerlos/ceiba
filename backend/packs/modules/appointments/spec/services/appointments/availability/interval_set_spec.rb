require "rails_helper"

RSpec.describe Appointments::Availability::IntervalSet do
  # Minute offsets from a fixed midnight keep the hand-derived expectations readable.
  def base = Time.utc(2026, 1, 5)

  def iv(from, to) = Appointments::Availability::Interval.new(starts_at: base + (from * 60), ends_at: base + (to * 60))

  def set(*pairs) = described_class.new(pairs.map { |from, to| iv(from, to) })

  def pairs(interval_set) = interval_set.intervals.map { |i| [ (i.starts_at - base).to_i / 60, (i.ends_at - base).to_i / 60 ] }

  describe "normalización" do
    it "ordena un conjunto desordenado" do
      expect(pairs(set([ 600, 660 ], [ 60, 120 ], [ 300, 360 ]))).to eq([ [ 60, 120 ], [ 300, 360 ], [ 600, 660 ] ])
    end

    it "fusiona solapes" do
      expect(pairs(set([ 60, 180 ], [ 120, 240 ], [ 100, 130 ]))).to eq([ [ 60, 240 ] ])
    end

    it "fusiona intervalos adyacentes" do
      expect(pairs(set([ 60, 120 ], [ 120, 180 ]))).to eq([ [ 60, 180 ] ])
    end

    it "conserva los tramos separados por un hueco de un minuto" do
      expect(pairs(set([ 60, 120 ], [ 121, 180 ]))).to eq([ [ 60, 120 ], [ 121, 180 ] ])
    end

    it "entrega un arreglo congelado y vacío para una lista vacía", :aggregate_failures do
      expect(set([ 60, 120 ]).intervals).to be_frozen
      expect(set).to be_empty
    end
  end

  describe "#subtract" do
    it "parte un tramo en dos" do
      expect(pairs(set([ 60, 300 ]).subtract(set([ 120, 180 ])))).to eq([ [ 60, 120 ], [ 180, 300 ] ])
    end

    it "queda vacío cuando la resta cubre todo" do
      expect(set([ 60, 120 ]).subtract(set([ 0, 600 ]))).to be_empty
    end

    it "no cambia nada con una resta disjunta o adyacente" do
      expect(set([ 60, 120 ]).subtract(set([ 120, 180 ], [ 0, 60 ], [ 500, 600 ]))).to eq(set([ 60, 120 ]))
    end

    it "recorta por los bordes y resta varios tramos a la vez" do
      result = set([ 0, 100 ], [ 200, 300 ]).subtract(set([ 0, 10 ], [ 90, 210 ], [ 290, 400 ]))

      expect(pairs(result)).to eq([ [ 10, 90 ], [ 210, 290 ] ])
    end

    it "un tramo restador largo afecta a varios tramos del minuendo" do
      expect(pairs(set([ 0, 10 ], [ 20, 30 ], [ 40, 50 ]).subtract(set([ 5, 45 ])))).to eq([ [ 0, 5 ], [ 45, 50 ] ])
    end
  end

  describe "#intersect" do
    it "devuelve el solape de dos conjuntos" do
      expect(pairs(set([ 60, 180 ], [ 300, 400 ]).intersect(set([ 120, 350 ])))).to eq([ [ 120, 180 ], [ 300, 350 ] ])
    end

    it "con un conjunto vacío devuelve vacío en ambos sentidos", :aggregate_failures do
      expect(set([ 60, 120 ]).intersect(set)).to be_empty
      expect(set.intersect(set([ 60, 120 ]))).to be_empty
    end

    it "es vacío para tramos que solo se tocan en el borde" do
      expect(set([ 60, 120 ]).intersect(set([ 120, 180 ]))).to be_empty
    end
  end

  describe "#union" do
    it "fusiona los dos conjuntos" do
      expect(pairs(set([ 60, 120 ]).union(set([ 120, 180 ], [ 300, 360 ])))).to eq([ [ 60, 180 ], [ 300, 360 ] ])
    end
  end

  describe "#cover?" do
    it "cubre un intervalo que cabe entero en un tramo, borde incluido", :aggregate_failures do
      expect(set([ 60, 180 ]).cover?(iv(60, 180))).to be(true)
      expect(set([ 0, 10 ], [ 60, 180 ]).cover?(iv(100, 130))).to be(true)
    end

    it "no cubre un intervalo que se reparte entre dos tramos separados" do
      expect(set([ 60, 120 ], [ 121, 180 ]).cover?(iv(100, 150))).to be(false)
    end

    it "no cubre uno que sobresale o cae fuera", :aggregate_failures do
      expect(set([ 60, 180 ]).cover?(iv(170, 181))).to be(false)
      expect(set([ 60, 180 ]).cover?(iv(200, 210))).to be(false)
      expect(set.cover?(iv(0, 1))).to be(false)
    end
  end

  describe "#==" do
    it "compara por contenido normalizado" do
      expect(set([ 60, 120 ], [ 120, 180 ])).to eq(set([ 60, 180 ]))
    end

    it "distingue conjuntos distintos" do
      expect(set([ 60, 120 ])).not_to eq(set([ 60, 121 ]))
    end
  end

  describe "propiedades (generadores propios)" do
    let(:seed) { Integer(ENV.fetch("AVAILABILITY_SEED") { Random.new_seed % 1_000_000 }) }
    let(:rng) { Random.new(seed) }

    def random_set(rng)
      count = rng.rand(0..6)
      list = Array.new(count) do
        from = rng.rand(0..200)
        iv(from, from + rng.rand(1..40))
      end
      described_class.new(list)
    end

    def normalized?(interval_set)
      list = interval_set.intervals
      list.each_cons(2).all? { |a, b| a.ends_at < b.starts_at } && list.all? { |i| i.starts_at < i.ends_at }
    end

    def each_pair(rng, count: 300)
      count.times { yield random_set(rng), random_set(rng) }
    end

    it "la unión y la intersección son conmutativas", :aggregate_failures do
      each_pair(rng) do |a, b|
        expect(a.union(b)).to eq(b.union(a)), "seed=#{seed}"
        expect(a.intersect(b)).to eq(b.intersect(a)), "seed=#{seed}"
      end
    end

    it "a - b nunca sale de a ni solapa b", :aggregate_failures do
      each_pair(rng) do |a, b|
        difference = a.subtract(b)

        expect(difference.intersect(b)).to be_empty, "seed=#{seed}"
        expect(difference.union(a)).to eq(a), "seed=#{seed}"
      end
    end

    it "(a - b) ∪ (a ∩ b) == a", :aggregate_failures do
      each_pair(rng) do |a, b|
        expect(a.subtract(b).union(a.intersect(b))).to eq(a), "seed=#{seed}"
      end
    end

    it "todo resultado está normalizado", :aggregate_failures do
      each_pair(rng) do |a, b|
        [ a.union(b), a.intersect(b), a.subtract(b) ].each do |result|
          expect(normalized?(result)).to be(true), "seed=#{seed}"
        end
      end
    end
  end
end
