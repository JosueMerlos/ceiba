require "rails_helper"

# Audit attribute diff: only what changed, no sensitive fields, encrypted PII masked.
RSpec.describe Audit::Diff do
  def diff(before:, after:, encrypted: []) = described_class.call(before:, after:, encrypted_attributes: encrypted)

  it "conserva solo los atributos que cambiaron, en before y en after" do
    result = diff(before: { "name" => "A", "status" => "active" }, after: { "name" => "B", "status" => "active" })

    expect(result).to eq(before: { "name" => "A" }, after: { "name" => "B" })
  end

  it "una creación (before nil) guarda todo en after y before nil" do
    expect(diff(before: nil, after: { "name" => "A" })).to eq(before: nil, after: { "name" => "A" })
  end

  it "un borrado (after nil) guarda todo en before y after nil" do
    expect(diff(before: { "name" => "A" }, after: nil)).to eq(before: { "name" => "A" }, after: nil)
  end

  it "una clave que aparece o desaparece cuenta como cambio" do
    expect(diff(before: { "a" => 1 }, after: { "b" => 2 })).to eq(before: { "a" => 1 }, after: { "b" => 2 })
  end

  it "acepta claves simbólicas y las normaliza a texto" do
    expect(diff(before: { name: "A" }, after: { name: "B" })).to eq(before: { "name" => "A" }, after: { "name" => "B" })
  end

  # The value becomes [FILTERED] but the KEY is kept (see Audit::Diff).
  describe "campos sensibles" do
    %w[password password_digest password_confirmation token token_digest session_token csrf_token secret client_secret otp_secret api_key
       api_key_digest private_key encryption_salt tls_certificate card_cvv ssn email name_ciphertext].each do |field|
      it "enmascara #{field} (antes y después), sin revelar ningún valor" do
        result = diff(before: { field => "valor-viejo", "name" => "A" }, after: { field => "valor-nuevo", "name" => "B" })

        expect(result).to eq(before: { field => "[FILTERED]", "name" => "A" }, after: { field => "[FILTERED]", "name" => "B" })
      end
    end

    it "en una creación también enmascara los sensibles" do
      expect(diff(before: nil, after: { "title" => "Ana", "password_digest" => "$2a$secreto" }))
        .to eq(before: nil, after: { "title" => "Ana", "password_digest" => "[FILTERED]" })
    end

    it "un sensible que NO cambió no aparece" do
      result = diff(before: { "token" => "t", "name" => "A" }, after: { "token" => "t", "name" => "B" })

      expect(result).to eq(before: { "name" => "A" }, after: { "name" => "B" })
    end

    it "nunca deja un valor sensible en el JSON resultante" do
      result = diff(before: { "password" => "viejo-1" }, after: { "password" => "nuevo-2" })

      expect(result.to_json).not_to match(/viejo-1|nuevo-2/)
    end
  end

  describe "estructuras anidadas (jsonb)" do
    it "enmascara los sensibles dentro de hashes anidados, conservando el resto" do
      before = { "settings" => { "whatsapp_token" => "tok-viejo", "language" => "es", "sms" => { "api_key" => "k-1", "sender" => "Ceiba" } } }
      after = { "settings" => { "whatsapp_token" => "tok-nuevo", "language" => "en", "sms" => { "api_key" => "k-2", "sender" => "Ceiba" } } }

      result = diff(before:, after:)

      expect(result[:after]).to eq("settings" => { "whatsapp_token" => "[FILTERED]", "language" => "en", "sms" => { "api_key" => "[FILTERED]", "sender" => "Ceiba" } })
      expect(result.to_json).not_to match(/tok-viejo|tok-nuevo|k-1|k-2/)
    end

    it "enmascara los sensibles dentro de arrays de hashes" do
      after = { "channels" => [ { "kind" => "sms", "secret" => "s-1" }, { "kind" => "wa", "token" => "t-1" } ] }

      result = diff(before: nil, after:)

      expect(result[:after]).to eq("channels" => [ { "kind" => "sms", "secret" => "[FILTERED]" }, { "kind" => "wa", "token" => "[FILTERED]" } ])
    end

    it "acepta claves simbólicas anidadas" do
      result = diff(before: nil, after: { config: { token: "t-1", mode: "x" } })

      expect(result[:after]).to eq("config" => { "token" => "[FILTERED]", "mode" => "x" })
    end

    it "un cambio SOLO en un secreto anidado deja la clave de primer nivel, con el secreto enmascarado" do
      result = diff(before: { "settings" => { "token" => "a" } }, after: { "settings" => { "token" => "b" } })

      expect(result).to eq(before: { "settings" => { "token" => "[FILTERED]" } }, after: { "settings" => { "token" => "[FILTERED]" } })
    end

    it "no modifica los hashes que recibe" do
      after = { "settings" => { "token" => "t" } }
      diff(before: nil, after:)

      expect(after).to eq("settings" => { "token" => "t" })
    end
  end

  describe "PII cifrada (criterio 5)" do
    it "enmascara como [FILTERED] el valor de un atributo cifrado que cambió, sin revelar ninguno de los dos" do
      result = diff(before: { "phone" => "+50588887777" }, after: { "phone" => "+50577776666" }, encrypted: [ :phone ])

      expect(result).to eq(before: { "phone" => "[FILTERED]" }, after: { "phone" => "[FILTERED]" })
      expect(result.to_json).not_to include("5058")
    end

    it "un atributo cifrado que NO cambió no aparece (ni siquiera enmascarado)" do
      result = diff(before: { "phone" => "+50588887777", "name" => "A" }, after: { "phone" => "+50588887777", "name" => "B" }, encrypted: [ :phone ])

      expect(result).to eq(before: { "name" => "A" }, after: { "name" => "B" })
    end

    it "en una creación enmascara el valor cifrado" do
      expect(diff(before: nil, after: { "phone" => "+50588887777" }, encrypted: %w[phone])).to eq(before: nil, after: { "phone" => "[FILTERED]" })
    end
  end
end
