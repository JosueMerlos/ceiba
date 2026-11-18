require "rails_helper"

# The guard only accepts JSON bodies, with ONE narrow exception: multipart/form-data on PATCH of a company's branding (logos
# cannot travel as JSON). A cross-site HTML form can only send GET or POST, so PATCH keeps that door closed; every other
# method, route and content type stays 415. Exercised against the middleware itself with a trivial app behind it.
RSpec.describe ApiRequestGuard do
  let(:inner) { ->(_env) { [ 200, { "Content-Type" => "text/plain" }, [ "passed" ] ] } }
  let(:guard) { described_class.new(inner) }
  let(:branding_path) { "/api/v1/organizations/0198f0a0-0000-7000-8000-000000000001/companies/0198f0a0-0000-7000-8000-000000000002/branding" }
  let(:boundary) { "----ceibaboundary" }
  let(:multipart) { "--#{boundary}\r\nContent-Disposition: form-data; name=\"brand_name\"\r\n\r\nSalón\r\n--#{boundary}--\r\n" }

  def request(method, path, content_type:, body: multipart)
    Rack::MockRequest.new(guard).request(method, path, "CONTENT_TYPE" => content_type, input: body)
  end

  def multipart_type = "multipart/form-data; boundary=#{boundary}"

  it "deja pasar multipart/form-data en PATCH de la ruta de marca de una empresa" do
    response = request("PATCH", branding_path, content_type: multipart_type)

    expect([ response.status, response.body ]).to eq([ 200, "passed" ])
  end

  it "rechaza multipart/form-data en POST de la misma ruta (415)" do
    expect(request("POST", branding_path, content_type: multipart_type).status).to eq(415)
  end

  it "rechaza multipart/form-data en PATCH de cualquier otra ruta (415)" do
    paths = [ "/api/v1/organizations/0198f0a0-0000-7000-8000-000000000001/companies/0198f0a0-0000-7000-8000-000000000002",
              "/api/v1/auth/login", "#{branding_path}/extra", "#{branding_path}x", "/api/v1/organizations/x/companies/y/branding" ]

    expect(paths.map { request("PATCH", it, content_type: multipart_type).status }).to all(eq(415))
  end

  it "en la ruta de marca sigue rechazando los otros tipos de contenido (415)" do
    statuses = [ "application/x-www-form-urlencoded", "text/plain" ].map { request("PATCH", branding_path, content_type: it, body: "a=1").status }

    expect(statuses).to all(eq(415))
  end

  it "en la ruta de marca sigue aceptando application/json" do
    expect(request("PATCH", branding_path, content_type: "application/json", body: "{}").status).to eq(200)
  end

  it "en la ruta de marca sigue rechazando parámetros en la query string (400)" do
    response = Rack::MockRequest.new(guard).request("PATCH", "#{branding_path}?brand_name=x", "CONTENT_TYPE" => multipart_type, input: multipart)

    expect(response.status).to eq(400)
  end

  describe "tamaño del cuerpo multipart (se rechaza antes de que Rack lo parsee)" do
    def sized_request(length, extra = {})
      env = { "CONTENT_TYPE" => multipart_type, input: "" }.merge(extra)
      env["CONTENT_LENGTH"] = length.to_s if length
      Rack::MockRequest.new(guard).request("PATCH", branding_path, env)
    end

    it "con Content-Length mayor de 8 MiB responde 413 problem+json request.too_large" do
      response = sized_request(8.megabytes + 1)

      expect([ response.status, response.media_type, JSON.parse(response.body)["code"] ]).to eq([ 413, "application/problem+json", "request.too_large" ])
    end

    it "con exactamente 8 MiB deja pasar" do
      expect(sized_request(8.megabytes).status).to eq(200)
    end
  end
end
