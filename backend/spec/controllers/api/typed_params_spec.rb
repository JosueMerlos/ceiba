require "rails_helper"

RSpec.describe Api::TypedParams do
  let(:host) do
    Class.new do
      include Api::TypedParams

      attr_reader :request, :params

      # `body` is what the JSON body carries; `query` is what the URL carries (merged into `params`, never into the body).
      def initialize(body, query = {})
        @request = Struct.new(:request_parameters).new(body.deep_stringify_keys)
        @params = ActionController::Parameters.new(query.merge(body))
      end

      def read(schema) = typed_params(schema)
    end
  end

  let(:schema) { { name: String, price_minor: Integer, active: :boolean } }

  def read(body, query = {}) = host.new(body, query).read(schema)

  it "devuelve con claves símbolo los valores bien tipados" do
    expect(read(name: "Corte", price_minor: 20_000, active: false)).to eq(name: "Corte", price_minor: 20_000, active: false)
  end

  it "devuelve solo las claves enviadas" do
    expect(read(name: "Corte")).to eq(name: "Corte")
  end

  it "descarta las claves que no están en el esquema" do
    expect(read(name: "Corte", company_id: "x", archived_at: "2026-01-01")).to eq(name: "Corte")
  end

  it "acepta null explícito en texto y entero (limpia el valor)" do
    expect(read(name: nil, price_minor: nil)).to eq(name: nil, price_minor: nil)
  end

  it "rechaza con 400 un valor del tipo equivocado y nombra el campo", :aggregate_failures do
    [ { name: 5 }, { price_minor: "20000" }, { price_minor: 1.5 }, { active: "true" }, { active: nil } ].each do |body|
      expect { read(body) }.to raise_error(ActionController::BadRequest, /#{body.keys.first}/)
    end
  end

  it "rechaza con 400 un arreglo u objeto en un campo escalar en vez de descartarlo", :aggregate_failures do
    [ { price_minor: [ 100 ] }, { price_minor: { a: 1 } }, { name: [ "Corte" ] }, { name: { a: 1 } }, { active: [ true ] } ].each do |body|
      expect { read(body) }.to raise_error(ActionController::BadRequest, /#{body.keys.first}/)
    end
  end

  it "rechaza con 400 un texto con byte nulo (la base de datos lo rechazaría con un 500)" do
    expect { read(name: "a\u0000b") }.to raise_error(ActionController::BadRequest, /name/)
  end

  it "lee solo el cuerpo: un valor de la query string no se mezcla" do
    expect(read({ name: "Corte" }, { name: "Query", price_minor: 1 })).to eq(name: "Corte")
  end
end
