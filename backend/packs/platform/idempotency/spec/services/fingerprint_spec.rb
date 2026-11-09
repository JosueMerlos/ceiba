require "rails_helper"

# Fingerprint de la petición (M0.11): método + ruta COMPLETA (con query) + cuerpo tal cual llegó. Los JSON se comparan por
# BYTES: dos serializaciones equivalentes con distinto orden de claves son peticiones distintas (un cliente que reintenta
# reenvía los mismos bytes). Los multipart no llegan: ApiRequestGuard exige application/json en toda mutación.
RSpec.describe Idempotency::Processor, ".fingerprint" do
  def request(path: "/api/v1/x", method: "POST", body: %({"a":1}))
    ActionDispatch::TestRequest.create("REQUEST_METHOD" => method, "PATH_INFO" => path.split("?").first, "QUERY_STRING" => path.split("?", 2)[1].to_s,
      "CONTENT_TYPE" => "application/json", "rack.input" => StringIO.new(body), "CONTENT_LENGTH" => body.bytesize.to_s)
  end

  it "es un SHA-256 hexadecimal" do
    expect(described_class.fingerprint(request)).to match(/\A\h{64}\z/)
  end

  it "es estable para la misma petición" do
    expect(described_class.fingerprint(request)).to eq(described_class.fingerprint(request))
  end

  it "cambia con el método, la ruta, la query y el cuerpo" do
    base = described_class.fingerprint(request)

    expect([ request(method: "PUT"), request(path: "/api/v1/y"), request(path: "/api/v1/x?b=2"), request(body: %({"a":2})) ].map { |r| described_class.fingerprint(r) })
      .to all(satisfy { |fingerprint| fingerprint != base })
  end

  it "el mismo JSON con otro orden de claves es otra petición (comparación por bytes)" do
    expect(described_class.fingerprint(request(body: %({"a":1,"b":2})))).not_to eq(described_class.fingerprint(request(body: %({"b":2,"a":1}))))
  end
end
