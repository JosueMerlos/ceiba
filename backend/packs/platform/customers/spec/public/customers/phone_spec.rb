require "rails_helper"

RSpec.describe Customers::Phone do
  describe ".normalize" do
    it "con un número local de Nicaragua devuelve el E.164 de la región" do
      expect(described_class.normalize("8888-7777", region: "NI")).to eq("+50588887777")
    end

    it "con prefijo internacional conserva el prefijo del número" do
      expect(described_class.normalize("+1 415 555 2671", region: "NI")).to eq("+14155552671")
    end

    it "con un valor inválido, vacío o nil devuelve nil" do
      expect([ "123", "", nil, "abcdefgh" ].map { |raw| described_class.normalize(raw, region: "NI") }).to all(be_nil)
    end
  end
end
