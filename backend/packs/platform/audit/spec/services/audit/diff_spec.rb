require "rails_helper"

# Diff de atributos de la auditoría (M0.11, criterio 5): solo lo que cambió, sin campos sensibles y con la PII cifrada
# enmascarada. Cubre el contrato de privacidad de docs/architecture/09-data-conventions.md y 11-security.md.
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

  describe "campos sensibles" do
    %w[password password_digest password_confirmation token token_digest session_token csrf_token secret client_secret otp_secret api_key_digest].each do |field|
      it "excluye #{field} por completo (ni la clave ni el valor)" do
        result = diff(before: { field => "viejo", "name" => "A" }, after: { field => "nuevo", "name" => "B" })

        expect(result.to_json).not_to include(field)
        expect(result.to_json).not_to include("viejo")
        expect(result.to_json).not_to include("nuevo")
      end
    end

    it "excluye los sensibles también en una creación" do
      expect(diff(before: nil, after: { "email" => "a@b.test", "password_digest" => "$2a$secreto" })).to eq(before: nil, after: { "email" => "a@b.test" })
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
