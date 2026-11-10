require "rails_helper"
require Rails.root.join("config/middleware/security_headers").to_s

RSpec.describe SecurityHeaders do
  let(:app) { ->(_env) { [ 200, { "X-Frame-Options" => "SAMEORIGIN" }, [ "ok" ] ] } }

  it "con hsts activo añade Strict-Transport-Security con preload" do
    _status, headers, = described_class.new(app, hsts: true).call(Rack::MockRequest.env_for("/api/health"))

    expect(headers["Strict-Transport-Security"]).to eq("max-age=63072000; includeSubDomains; preload")
  end

  it "pisa una cabecera más laxa que ponga la aplicación (X-Frame-Options)" do
    _status, headers, = described_class.new(app, hsts: false).call(Rack::MockRequest.env_for("/api/health"))

    expect(headers["X-Frame-Options"]).to eq("DENY")
  end
end
