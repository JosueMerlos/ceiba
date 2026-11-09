require "swagger_helper"

# rswag exige que el `let` se llame igual que el parámetro de cabecera (`X-CSRF-Token`).
# rubocop:disable RSpec/VariableName, RSpec/VariableDefinition

# Contrato de los endpoints de autenticación (M0.07). Cada `response` ejecuta la petición real y valida el cuerpo contra
# el esquema; de aquí sale backend/openapi/v1.yaml.
RSpec.describe "API v1: autenticación" do
  let(:user) { create(:user, email: "ana@ceiba.test", password: "contraseña-segura-1") }

  # La cookie de sesión y el token CSRF viajan por el jar de la sesión de integración: se inicia sesión de verdad.
  path "/api/v1/auth/login" do
    post "Inicia sesión" do
      tags "Autenticación"
      description "Correo y contraseña. Entrega la cookie de sesión (`HttpOnly`, `SameSite=Lax`, `Secure` en producción) y el token CSRF. " \
                  "Un correo inexistente y una contraseña errónea dan EXACTAMENTE la misma respuesta."
      consumes "application/json"
      produces "application/json", "application/problem+json"
      parameter name: :credentials, in: :body, required: true, schema: {
        type: :object, properties: { email: { type: :string, format: :email }, password: { type: :string, format: :password } },
        required: %w[email password]
      }

      response "200", "sesión iniciada" do
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/AuthSession" } }, required: %w[data], additionalProperties: false
        let(:credentials) { { email: user.email, password: "contraseña-segura-1" } }

        run_test! do |response|
          expect(response.headers["Set-Cookie"]).to match(/#{Api::SessionCookie.name}=/)
        end
      end

      response "401", "credenciales inválidas (código `auth.invalid_credentials`)" do
        schema "$ref" => "#/components/schemas/Problem"
        let(:credentials) { { email: "nadie@ceiba.test", password: "contraseña-segura-1" } }

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.invalid_credentials") }
      end

      response "400", "faltan el correo o la contraseña" do
        schema "$ref" => "#/components/schemas/ValidationProblem"
        let(:credentials) { { email: "ana@ceiba.test" } }

        run_test!
      end
    end
  end

  path "/api/v1/auth/session" do
    get "Sesión actual" do
      tags "Autenticación"
      description "Quién es el usuario autenticado y su token CSRF. La SPA lo llama al arrancar para recuperar el token."
      produces "application/json", "application/problem+json"
      security [ { cookieAuth: [] } ]

      response "200", "la sesión vigente" do
        schema type: :object, properties: { data: { "$ref" => "#/components/schemas/AuthSession" } }, required: %w[data], additionalProperties: false
        let!(:signed_in) { sign_in(user) }

        run_test! { |response| expect(response.parsed_body.dig("data", "csrf_token")).to eq(signed_in.csrf_token) }
      end

      response "401", "sin sesión válida (ausente, vencida o revocada; código `auth.unauthenticated`)" do
        schema "$ref" => "#/components/schemas/Problem"

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.unauthenticated") }
      end
    end
  end

  path "/api/v1/auth/logout" do
    delete "Cierra la sesión actual" do
      tags "Autenticación"
      description "Revoca la sesión del navegador y borra la cookie. Las demás sesiones del usuario siguen vigentes."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "sesión cerrada" do
        let("X-CSRF-Token") { signed_in.csrf_token }
        let!(:signed_in) { sign_in(user) }

        run_test!
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"
        let("X-CSRF-Token") { "sin-sesion" }

        run_test!
      end

      response "403", "sesión válida sin token CSRF correcto (`auth.csrf_invalid`) o con `Origin` ajeno (`auth.origin_forbidden`)" do
        schema "$ref" => "#/components/schemas/Problem"
        let!(:signed_in) { sign_in(user) }
        let("X-CSRF-Token") { "token-incorrecto" }

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.csrf_invalid") }
      end
    end
  end

  path "/api/v1/auth/sessions" do
    delete "Cierra todas las sesiones" do
      tags "Autenticación"
      description "Revoca todas las sesiones del usuario, en todos los dispositivos."
      produces "application/problem+json"
      security [ { cookieAuth: [] } ]
      parameter name: "X-CSRF-Token", in: :header, type: :string, required: true, description: "`csrf_token` de la sesión (login o GET /auth/session)"

      response "204", "todas las sesiones revocadas" do
        let("X-CSRF-Token") { signed_in.csrf_token }
        let!(:signed_in) { sign_in(user) }

        run_test!
      end

      response "401", "sin sesión válida" do
        schema "$ref" => "#/components/schemas/Problem"
        let("X-CSRF-Token") { "sin-sesion" }

        run_test!
      end

      response "403", "sesión válida sin token CSRF correcto (`auth.csrf_invalid`) o con `Origin` ajeno (`auth.origin_forbidden`)" do
        schema "$ref" => "#/components/schemas/Problem"
        let!(:signed_in) { sign_in(user) }
        let("X-CSRF-Token") { "token-incorrecto" }

        run_test! { |response| expect(response.parsed_body["code"]).to eq("auth.csrf_invalid") }
      end
    end
  end
end
# rubocop:enable RSpec/VariableName, RSpec/VariableDefinition
