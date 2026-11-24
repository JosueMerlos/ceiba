require "rails_helper"

# No personal data or secret reaches a log or Sentry through a request's parameters. Rails' filter matches the KEY
# partially (:passw filters password, password_confirmation...).
RSpec.describe "config.filter_parameters" do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  {
    "contraseña" => %w[password contraseña contrasena password_confirmation new_password],
    "token" => %w[token csrf_token reset_token api_token],
    "teléfono" => %w[phone phone_number teléfono telefono celular mobile whatsapp],
    "correo" => %w[email correo correo_electronico],
    "otp" => %w[otp otp_code],
    "notas de clientes" => %w[notes customer_notes],
    "nombre de clientes" => %w[full_name customer_full_name name_prefix],
    "motivo de ausencias" => %w[reason absence_reason]
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

  it "filtra el contacto del profesional anidado en su cuerpo" do
    filtered = filter.filter("professional" => { "display_name" => "Ana", "phone" => "+50588881234", "email" => "ana@ej.com" })

    expect(filtered).to eq("professional" => { "display_name" => "Ana", "phone" => "[FILTERED]", "email" => "[FILTERED]" })
  end

  it "no filtra parámetros que no son sensibles" do
    expect(filter.filter("slug" => "clinica-sol", "limit" => "20", "name" => "Corte", "q" => "x"))
      .to eq("slug" => "clinica-sol", "limit" => "20", "name" => "Corte", "q" => "x")
  end
end
