require "rails_helper"

# The only Active Storage route is the GET representation proxy under /api/storage, answering variants the application
# already rendered. No route writes (direct uploads, disk PUT), no route serves an original, and an anonymous GET never makes
# the server process an image.
RSpec.describe "Rutas de archivos (/api/storage)" do
  let(:organization) { create(:organization) }
  let(:company) { create_in(organization, :company) }

  def attach_logo(process: true)
    with_tenant(organization) do
      company.logo.attach(io: StringIO.new(png_bytes(width: 300, height: 300)), filename: "logo.png", content_type: "image/png", identify: false)
      company.logo.variant(:x1).processed if process
      company.reload
    end
  end

  def x1_path(blob: company.logo.blob)
    Rails.application.routes.url_helpers.rails_blob_representation_proxy_path(
      signed_blob_id: blob.signed_id, variation_key: company.logo.variant(:x1).variation.key, filename: blob.filename
    )
  end

  it "sirve una variante ya procesada como image/webp, pública e inmutable" do
    attach_logo

    get x1_path

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    expect(response.headers["Cache-Control"]).to include("public").and include("max-age=31536000").and include("immutable")
  end

  it "la URL sale bajo /api/storage" do
    attach_logo

    expect(x1_path).to start_with("/api/storage/representations/proxy/")
  end

  it "es anónima: no pide sesión" do
    attach_logo

    get x1_path

    expect(response).not_to have_http_status(:unauthorized)
  end

  it "responde 404 si la variante no está procesada, sin procesarla ni escribir nada (un GET anónimo no ejecuta vips)" do
    attach_logo(process: false)
    path = x1_path

    expect { get path }.not_to change { [ ActiveStorage::VariantRecord.count, ActiveStorage::Blob.count ] }

    expect(response).to have_http_status(:not_found)
  end

  it "responde 404 con una firma de blob inválida" do
    attach_logo

    get x1_path.sub(%r{proxy/[^/]+/}, "proxy/firma-falsa/")

    expect(response).to have_http_status(:not_found)
  end

  it "responde 404 con una transformación que el servidor no firmó" do
    attach_logo
    forged = ActiveStorage::Variation.encode(resize_to_limit: [ 9999, 9999 ])

    get x1_path.sub(%r{(proxy/[^/]+/)[^/]+/}, "\\1#{forged}/")

    expect(response).to have_http_status(:not_found)
  end

  it "no procesa en la petición ni encola trabajos al servir" do
    attach_logo
    Sidekiq::Queues.clear_all

    get x1_path

    expect(Sidekiq::Queues.jobs_by_queue.values.flatten).to be_empty
  end

  describe "superficie del router" do
    let(:storage_routes) do
      Rails.application.routes.routes.select { |route| route.path.spec.to_s.match?(%r{active_storage|/storage/}) }.map { |route| "#{route.verb} #{route.path.spec.to_s.sub('(.:format)', '')}" }
    end

    it "la única ruta de ActiveStorage es el GET del proxy de representaciones" do
      expect(storage_routes).to eq([ "GET /api/storage/representations/proxy/:signed_blob_id/:variation_key/*filename" ])
    end

    it "no existen las subidas directas ni el PUT del disco" do
      post "/api/storage/direct_uploads", as: :json
      posted = response.status
      put "/api/storage/disk/token"

      expect([ posted, response.status ]).to eq([ 404, 404 ])
    end

    it "no hay proxy ni redirección del original: el blob no tiene URL pública" do
      attach_logo

      get "/api/storage/blobs/proxy/#{company.logo.blob.signed_id}/logo.png"

      expect(response).to have_http_status(:not_found)
    end

    it "tampoco existen las rutas por defecto de Rails (/rails/active_storage)" do
      attach_logo

      get "/rails/active_storage/blobs/proxy/#{company.logo.blob.signed_id}/logo.png"

      expect(response).to have_http_status(:not_found)
    end
  end
end
