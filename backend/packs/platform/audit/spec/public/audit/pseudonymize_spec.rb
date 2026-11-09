require "rails_helper"

# Audit.pseudonymize (M0.11): seudónimo estable de un dato personal para correlacionar eventos sin guardarlo. HMAC-SHA256 con
# una clave derivada de secret_key_base (como el token CSRF): sin la clave no se puede confirmar por fuerza bruta que un
# correo concreto intentó entrar, a diferencia de un SHA-256 simple.
RSpec.describe "Audit.pseudonymize" do
  it "es un HMAC-SHA256 hexadecimal con clave derivada de la aplicación, no un SHA-256 simple" do
    value = "nadie@ceiba.test"
    key = Rails.application.key_generator.generate_key("ceiba/audit/pseudonym", 32)

    expect(Audit.pseudonymize(value)).to eq(OpenSSL::HMAC.hexdigest("SHA256", key, value))
    expect(Audit.pseudonymize(value)).not_to eq(OpenSSL::Digest::SHA256.hexdigest(value))
  end

  it "es estable y distingue valores" do
    first = Audit.pseudonymize("a")

    expect(Audit.pseudonymize("a")).to eq(first)
    expect(Audit.pseudonymize("a")).not_to eq(Audit.pseudonymize("b"))
  end
end
