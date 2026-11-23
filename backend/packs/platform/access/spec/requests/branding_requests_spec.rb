require "rails_helper"

# The real multipart wire format of PATCH .../branding (the rswag spec posts a hash), what a JSON PATCH does, the `remove[]`
# list, the audit trail and the log: an upload must never be dumped into the log as a parameter.
RSpec.describe "Marca de la empresa: peticiones reales" do
  let(:world) { build_access_world }
  let(:company) { world.company_a }
  let(:signed_in) { sign_in(user_with_role("company_manager", world, company: company)) }
  let(:path) { "/api/v1/organizations/#{world.organization.id}/companies/#{company.id}/branding" }

  def png_file(color: [ 47, 138, 102 ], name: "logo.png")
    Rack::Test::UploadedFile.new(StringIO.new(png_bytes(width: 300, height: 300, color:)), "image/png", original_filename: name)
  end

  def reloaded = with_tenant(world.organization) { company.reload }

  def patch_branding(params, session: signed_in) = patch(path, params:, headers: session.csrf_headers)

  def patch_json(params) = patch(path, params:, headers: signed_in.csrf_headers, as: :json)

  it "un cuerpo multipart de más de 8 MiB responde 413 request.too_large y no guarda nada" do
    big = Rack::Test::UploadedFile.new(StringIO.new("0" * (8.megabytes + 1)), "image/png", original_filename: "logo.png")

    patch_branding({ brand_name: "Nuevo", logo: big })

    expect([ response.status, response.parsed_body["code"], reloaded.brand_name ]).to eq([ 413, "request.too_large", nil ])
  end

  it "guarda textos y logo enviados como multipart y devuelve la marca" do
    patch_branding({ brand_name: "Salón Estilo", primary_color: "#ffff00", logo: png_file })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"]).to include("brand_name" => "Salón Estilo", "primary_color" => "#FFFF00")
    expect(with_tenant(world.organization) { company.reload.logo.attached? }).to be(true)
  end

  it "un campo enviado vacío vuelve al default" do
    patch_json({ primary_color: "#FFFF00", tagline: "Corte" })

    patch_json({ primary_color: "" })

    expect(reloaded.attributes.values_at("primary_color", "tagline")).to eq([ nil, "Corte" ])
  end

  it "lo que no se envía no cambia" do
    patch_json({ primary_color: "#FFFF00", tagline: "Corte" })

    patch_json({ tagline: "Color" })

    expect(reloaded.attributes.values_at("primary_color", "tagline")).to eq([ "#FFFF00", "Color" ])
  end

  it "remove[] quita el logo" do
    patch_branding({ logo: png_file })

    patch path, params: { remove: [ "logo" ] }, headers: signed_in.csrf_headers, as: :json

    expect([ response.status, reloaded.logo.attached? ]).to eq([ 200, false ])
  end

  it "remove[] también viaja en multipart junto a un archivo nuevo" do
    patch_branding({ banner: png_file, logo: png_file })

    patch_branding({ remove: [ "banner" ], favicon: png_file })

    expect(with_tenant(world.organization) { company.reload.then { [ it.banner.attached?, it.logo.attached?, it.favicon.attached? ] } }).to eq([ false, true, true ])
  end

  it "remove[] con algo que no es un adjunto de marca responde 400" do
    patch path, params: { remove: [ "organization" ] }, headers: signed_in.csrf_headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "un archivo enviado como texto (no como subida) responde 400" do
    patch path, params: { logo: "no-soy-un-archivo" }, headers: signed_in.csrf_headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "acepta también un PATCH JSON sin archivos (valores nulos vuelven al default)" do
    patch_json({ primary_color: "#FFFF00" })

    patch path, params: { primary_color: nil, brand_name: "Solo JSON" }, headers: signed_in.csrf_headers, as: :json

    expect([ response.status, reloaded.attributes.values_at("primary_color", "brand_name") ]).to eq([ 200, [ nil, "Solo JSON" ] ])
  end

  it "un valor que no es texto responde 400" do
    patch path, params: { primary_color: [ "#FFFF00" ] }, headers: signed_in.csrf_headers, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it "un POST multipart a la misma ruta responde 415 (solo PATCH está exceptuado)" do
    post path, params: { brand_name: "x", logo: png_file }, headers: signed_in.csrf_headers

    expect(response).to have_http_status(:unsupported_media_type)
  end

  it "el log de la petición no vuelca el binario ni el objeto de la subida" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io, level: :debug)
    session = signed_in
    Rails.logger.broadcast_to(logger)

    patch_branding({ logo: png_file }, session:)

    expect(io.string.b).to include("BrandingsController")
    expect(io.string.b).not_to include("\x89PNG".b)
    expect(io.string).not_to include("UploadedFile")
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end
end
