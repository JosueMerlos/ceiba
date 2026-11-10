require "rails_helper"

# Audit.pseudonymize: stable pseudonym of personal data to correlate events without storing it. HMAC-SHA256 keyed from
# secret_key_base (like the CSRF token): unlike a plain SHA-256, without the key one cannot brute-force-confirm that a
# given email tried to log in.
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
