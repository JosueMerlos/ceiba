require "rails_helper"

# Rails in API mode ships neither cookies nor CSRF protection: they are included explicitly.
RSpec.describe "Configuración de autenticación" do
  it "incluye ActionDispatch::Cookies en la pila de middleware (modo API no lo trae)" do
    expect(Rails.application.middleware.map(&:klass)).to include(ActionDispatch::Cookies)
  end

  it "no activa la sesión de Rails ni el flash: la sesión es la tabla sessions (ADR-0017)" do
    middleware = Rails.application.middleware.map(&:klass)

    expect(middleware).not_to include(ActionDispatch::Session::CookieStore)
    expect(middleware).not_to include(ActionDispatch::Flash)
  end

  it "Api::BaseController incluye la autenticación (deny by default)" do
    expect(Api::BaseController.ancestors).to include(Api::Authentication)
    expect(Api::BaseController._process_action_callbacks.map(&:filter)).to include(:authenticate!)
  end

  it "la cookie Secure y con prefijo __Host- queda activa en producción" do
    expect(File.read(Rails.root.join("config/initializers/authentication.rb"))).to include("secure_cookies = Rails.env.production?")
  end
end
