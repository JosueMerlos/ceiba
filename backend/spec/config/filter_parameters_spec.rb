require "rails_helper"

# M0.13: ningún dato personal ni secreto llega a un log o a Sentry por los parámetros de una request. El filtro de
# Rails es por coincidencia parcial de la CLAVE (:passw filtra password, password_confirmation...).
RSpec.describe "config.filter_parameters" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  {
    "contraseña" => %w[password contraseña contrasena password_confirmation new_password],
    "token" => %w[token csrf_token reset_token api_token],
    "teléfono" => %w[phone phone_number teléfono telefono celular mobile whatsapp],
    "correo" => %w[email correo correo_electronico],
    "otp" => %w[otp otp_code]
  }.each do |category, keys|
    it "filtra los parámetros de #{category}" do
      keys.each do |key|
        expect(filter.filter(key => "valor-sensible")).to eq(key => "[FILTERED]"), "#{key} no se filtra"
      end
    end
  end

  it "filtra también los valores anidados" do
    filtered = filter.filter("user" => { "email" => "ana@example.com", "name" => "Ana" })

    expect(filtered).to eq("user" => { "email" => "[FILTERED]", "name" => "Ana" })
  end

  it "no filtra parámetros que no son sensibles" do
    expect(filter.filter("slug" => "clinica-sol", "limit" => "20")).to eq("slug" => "clinica-sol", "limit" => "20")
  end
end
