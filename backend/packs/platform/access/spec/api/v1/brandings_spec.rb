require "swagger_helper"

# A company's branding (colors, font, texts and the logo/banner/favicon images), edited from the panel with
# `platform.branding.update`. The PATCH is multipart/form-data (the only mutation that is not JSON). A company outside the
# user's reach, or in another organization, is a 404; a visible company without the permission is a 403.
# rswag requires the `let` to be named like the header parameter (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
RSpec.describe "API v1: marca de la empresa" do
  let(:world) { build_access_world }
  let(:organization_id) { world.organization.id }
  let(:company_id) { world.company_a.id }
  let(:manager) { user_with_role("company_manager", world, company: world.company_a) }
  let("X-CSRF-Token") { signed_in.csrf_token }

  single_schema = { type: :object, required: %w[data], additionalProperties: false, properties: { data: { "$ref" => "#/components/schemas/Branding" } } }

  def png_upload(name: "logo.png", type: "image/png")
    Rack::Test::UploadedFile.new(StringIO.new(png_bytes(width: 300, height: 300)), type, original_filename: name)
  end

  def svg_as_png
    Rack::Test::UploadedFile.new(StringIO.new(BrandingImages::SVG), "image/png", original_filename: "svg-as.png")
  end

  path "/api/v1/organizations/{organization_id}/companies/{company_id}/branding" do
    parameter name: :organization_id, in: :path, schema: { type: :string, format: :uuid }, required: true
    parameter name: :company_id, in: :path, schema: { type: :string, format: :uuid }, required: true

    get "Obtiene la marca de la empresa" do
      tags "Marca"
      description "Exige `platform.branding.update` (org_admin y company_manager de la empresa). Una empresa fuera del alcance del usuario responde 404; " \
                  "una visible sin el permiso, 403. Los campos sin personalizar son `null`: se usa la paleta de la plataforma."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la marca (todo `null` si la empresa no la personalizó)" do
        let!(:signed_in) { sign_in(manager) }
        schema single_schema

        run_test! do |response|
          expect(response.parsed_body["data"]).to eq(
            "brand_name" => nil, "tagline" => nil, "primary_color" => nil, "secondary_color" => nil, "accent_color" => nil, "font_choice" => nil,
            "assets" => { "logo" => nil, "banner" => nil, "favicon" => nil }
          )
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "visible pero sin `platform.branding.update` (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("access.forbidden") }
      end

      response "404", "la empresa está fuera del alcance del usuario, o en otra organización" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_b)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end
    end

    patch "Edita la marca de la empresa" do
      tags "Marca"
      description "Exige `platform.branding.update`. Es `multipart/form-data`: textos, colores `#RRGGBB`, `font_choice` (`figtree`, `lora` o `nunito`) y los archivos " \
                  "`logo`, `banner` y `favicon` (PNG, JPEG o WebP, validados por su contenido real, no por su nombre ni su tipo declarado). Solo cambia lo enviado; " \
                  "un campo vacío vuelve al default de la plataforma y `remove[]` quita un archivo. Archivos y datos se validan antes de guardar nada: o se aplica todo o nada."
      consumes "multipart/form-data"
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"
      # rswag builds the multipart payload from the formData parameters (one per field) and takes the request body's schema from the
      # FIRST one: it carries the schema of the whole body, the others only name their field.
      parameter name: :brand_name, in: :formData, required: true, schema: { "$ref" => "#/components/schemas/BrandingUpdate" }
      parameter name: :tagline, in: :formData, type: :string, required: false
      parameter name: :primary_color, in: :formData, type: :string, required: false
      parameter name: :secondary_color, in: :formData, type: :string, required: false
      parameter name: :accent_color, in: :formData, type: :string, required: false
      parameter name: :font_choice, in: :formData, type: :string, required: false
      parameter name: :logo, in: :formData, type: :file, required: false
      parameter name: :banner, in: :formData, type: :file, required: false
      parameter name: :favicon, in: :formData, type: :file, required: false

      let(:brand_name) { "Salón Estilo" }
      let(:tagline) { nil }
      let(:primary_color) { "#ffff00" }
      let(:secondary_color) { nil }
      let(:accent_color) { nil }
      let(:font_choice) { "lora" }
      let(:logo) { png_upload }
      let(:banner) { nil }
      let(:favicon) { nil }

      response "200", "la marca guardada, con las URLs versionadas de las variantes" do
        let!(:signed_in) { sign_in(user_with_role("org_admin", world)) }
        schema single_schema

        run_test! do |response|
          data = response.parsed_body["data"]
          expect(data).to include("brand_name" => "Salón Estilo", "primary_color" => "#FFFF00", "font_choice" => "lora")
          expect(data["assets"].slice("banner", "favicon")).to eq("banner" => nil, "favicon" => nil)
          expect(data.dig("assets", "logo").keys).to eq(%w[x1 x2])
          expect(data.dig("assets", "logo", "x1")).to start_with("/api/storage/representations/proxy/")
          expect(with_tenant(world.organization) { world.company_a.reload.logo.attached? }).to be(true)
          expect(with_tenant(world.organization) { Audit::Event.where(action: "company.branding_updated").count }).to eq(1)
        end
      end

      response "401", "sin sesión válida" do
        let!(:signed_in) { Struct.new(:csrf_token).new("sin-sesion") }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end

      response "403", "falta el token CSRF (`auth.csrf_invalid`)" do
        let!(:signed_in) { sign_in(manager) }
        let("X-CSRF-Token") { "token-incorrecto" }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("auth.csrf_invalid")
          expect(with_tenant(world.organization) { world.company_a.reload.primary_color }).to be_nil
        end
      end

      response "403", "el branch_manager no tiene `platform.branding.update` (`access.forbidden`)" do
        let!(:signed_in) { sign_in(user_with_role("branch_manager", world, branch: world.branch_a1)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("access.forbidden")
          expect(with_tenant(world.organization) { world.company_a.reload.attributes.values_at("primary_color", "brand_name") }).to eq([ nil, nil ])
        end
      end

      response "404", "la empresa es de otra empresa o de otra organización" do
        let!(:signed_in) { sign_in(user_with_role("company_manager", world, company: world.company_b)) }
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("resource.not_found") }
      end

      # rswag posts a hash, not a real multipart body, so the guard cannot be exercised through it; the 413 is declared here for
      # the contract and its wire behavior (a real oversized multipart body) is covered in spec/requests (branding_requests_spec).
      response "413", "el cuerpo supera los 8 MiB (`request.too_large`); se rechaza antes de parsearlo" do
        schema "$ref" => "#/components/schemas/Problem"

        it "declara la respuesta en el contrato" do |example|
          expect(example.metadata.dig(:response, :code)).to eq("413")
        end
      end

      response "422", "un archivo que no es una imagen PNG, JPEG o WebP (un SVG renombrado a .png) o un color inválido" do
        let!(:signed_in) { sign_in(manager) }
        let(:logo) { svg_as_png }
        let(:accent_color) { "amarillo" }
        schema "$ref" => "#/components/schemas/ValidationProblem"

        run_test! do |response|
          expect(response.parsed_body["code"]).to eq("validation.failed")
          expect(response.parsed_body["errors"].map { it.slice("field", "code") }).to contain_exactly(
            { "field" => "accent_color", "code" => "invalid" }, { "field" => "logo", "code" => "invalid_file_type" }
          )
          expect(with_tenant(world.organization) { world.company_a.reload.primary_color }).to be_nil
        end
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition, RSpec/MultipleMemoizedHelpers
