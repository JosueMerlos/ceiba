require "swagger_helper"

# PUBLIC branding: anonymous, by the company's slug, so the booking page (and the panel) can paint a company's identity. It
# answers with an ETag and `Cache-Control: public, no-cache`: the browser always revalidates (a cheap 304) and never keeps a
# stale brand after a change. A company with no branding answers 200 with every field null (the platform palette applies).
# An unknown slug, a suspended organization and an inactive company answer the same 404.
RSpec.describe "API pública v1: marca de la empresa" do
  let(:organization) { create(:organization) }
  let!(:company) { create_in(organization, :company, slug: "salon-estilo") }
  let(:slug) { "salon-estilo" }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Branding" } } }

  def attach_logo(color: [ 47, 138, 102 ]) = attach_branding_image(organization, company, :logo, color:)

  def fetch(headers: {}) = get("/api/public/v1/c/#{slug}/branding", headers:)

  path "/api/public/v1/c/{slug}/branding" do
    parameter name: :slug, in: :path, schema: { type: :string }, required: true, description: "Slug público de la empresa"

    get "Marca de la empresa" do
      tags "Reserva pública"
      description "Anónimo. Responde con `ETag` y `Cache-Control: public, no-cache`: el navegador revalida siempre y una marca cambiada se ve sin limpiar la caché " \
                  "(las URLs de los archivos cambian con cada archivo nuevo). Los campos sin personalizar son `null`: se usa la paleta de la plataforma. " \
                  "Un slug inexistente, una organización suspendida y una empresa inactiva responden el mismo 404."
      produces "application/json", "application/problem+json"

      response "200", "la marca, con las URLs versionadas de las variantes" do
        before do
          with_tenant(organization) { company.update!(brand_name: "Salón Estilo", primary_color: "#1D6C4E", font_choice: "nunito") }
          attach_logo
        end

        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("brand_name" => "Salón Estilo", "primary_color" => "#1D6C4E", "font_choice" => "nunito")
          expect(data["assets"].slice("banner", "favicon")).to eq("banner" => nil, "favicon" => nil)
          expect(data.dig("assets", "logo").values).to all(start_with("/api/storage/representations/proxy/"))
          expect(response.headers["Cache-Control"]).to eq("public, no-cache")
          expect(response.headers["ETag"]).to be_present
        end
      end

      response "404", "el slug no existe, la organización está suspendida o la empresa está inactiva" do
        let(:slug) { "no-existe" }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end
  end

  describe "una empresa sin marca" do
    it "responde 200 con todos los campos null (paleta de la plataforma)" do
      fetch

      expect([ response.status, response.parsed_body["data"] ]).to eq(
        [ 200, { "brand_name" => nil, "tagline" => nil, "primary_color" => nil, "secondary_color" => nil, "accent_color" => nil, "font_choice" => nil,
                 "assets" => { "logo" => nil, "banner" => nil, "favicon" => nil } } ]
      )
    end
  end

  describe "puertas cerradas" do
    def answer = [ response.status, response.parsed_body.except("request_id", "instance") ]

    it "responden exactamente el mismo cuerpo (no revelan cuál estaba cerrada)" do
      get "/api/public/v1/c/no-existe/branding"
      unknown = answer
      organization.update!(status: "suspended")
      fetch
      suspended = answer
      organization.update!(status: "active")
      with_tenant(organization) { company.update!(status: "inactive") }
      fetch

      expect([ suspended, answer ]).to all(eq(unknown))
      expect(unknown.first).to eq(404)
    end
  end

  describe "revalidación" do
    it "una segunda petición con If-None-Match responde 304 sin cuerpo" do
      attach_logo
      fetch
      etag = response.headers["ETag"]

      fetch(headers: { "If-None-Match" => etag })

      expect([ response.status, response.body ]).to eq([ 304, "" ])
    end

    it "tras reemplazar el logo, el ETag cambia y la URL del logo es otra" do
      attach_logo
      fetch
      before = [ response.headers["ETag"], response.parsed_body.dig("data", "assets", "logo", "x1") ]

      attach_logo(color: [ 200, 20, 20 ])
      fetch(headers: { "If-None-Match" => before.first })

      expect(response).to have_http_status(:ok)
      expect([ response.headers["ETag"], response.parsed_body.dig("data", "assets", "logo", "x1") ]).to all(satisfy { |value| !before.include?(value) })
    end

    it "tras cambiar solo un color, el ETag cambia" do
      fetch
      etag = response.headers["ETag"]

      with_tenant(organization) { company.update!(primary_color: "#1D6C4E") }
      fetch(headers: { "If-None-Match" => etag })

      expect(response).to have_http_status(:ok)
    end

    it "la lectura no escribe nada ni encola trabajos" do
      attach_logo
      Sidekiq::Queues.clear_all

      expect { fetch }.not_to change { [ ActiveStorage::Blob.count, ActiveStorage::VariantRecord.count, with_tenant(organization) { Audit::Event.count }, Sidekiq::Queues.jobs_by_queue.values.flatten.size ] }
    end
  end
end
