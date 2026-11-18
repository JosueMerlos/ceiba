require "rails_helper"

# Puma buffers a request body before Rack (and the app's middleware) sees it, so its own cap is the real backstop against an
# oversized upload. It must match the cap of the branding upload, the largest body the API accepts.
RSpec.describe "config/puma.rb" do
  it "limita el cuerpo de cualquier petición a 8 MiB" do
    configuration = Puma::Configuration.new({ config_files: [ Rails.root.join("config/puma.rb").to_s ] }, {}).tap(&:load).tap(&:clamp)

    expect(configuration.options[:http_content_length_limit]).to eq(ApiRequestGuard::MAX_MULTIPART_BYTES)
  end
end
